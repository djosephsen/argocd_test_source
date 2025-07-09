package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/myprizepicks/releasechannels-server-poc/internal/db"
	"github.com/rs/zerolog"
)

// Server is the interface for a releasechan api server
type Server interface {
	Run(context.Context) error
	ReloadDatabase() error
}

// srv implements Server
type srv struct {
	db        db.Store
	dbFile    string
	lastMod   time.Time
	closeChan chan struct{}
	ll        *zerolog.Logger
}

// srv explicitly implements Server
var _ Server = &srv{}

// New is a constructor for an srv-backed Server
func New(data []byte, dbFile string, gl *zerolog.Logger) (Server, error) {
	ll := gl.With().Str("package", "server").Logger()
	ll.Info().Int("bytes_in", len(data)).Msg("Server Started")

	// Get initial file mod time
	var lastMod time.Time
	if stat, err := os.Stat(dbFile); err == nil {
		lastMod = stat.ModTime()
	}

	// construct the srv
	out := &srv{
		db:        db.NewInMemoryStore(gl),
		dbFile:    dbFile,
		lastMod:   lastMod,
		closeChan: make(chan struct{}),
		ll:        &ll,
	}

	// Load initial data
	if err := out.loadDatabase(data); err != nil {
		return nil, err
	}

	return out, nil
}

// loadDatabase loads release data into the database
func (s *srv) loadDatabase(data []byte) error {
	// Create new database instance
	s.db = db.NewInMemoryStore(s.ll)

	// marshal the test-data into a []db.Release
	releasesIn := struct {
		Releases db.Releases `json:"releases"`
	}{
		Releases: db.Releases{},
	}
	if err := json.Unmarshal(data, &releasesIn); err != nil {
		s.ll.Error().Err(err).Msg("error unmarshalling input")
		return err
	}

	// load the test-data into our DB
	for _, r := range releasesIn.Releases {
		err := s.db.Write(r)
		if err != nil {
			s.ll.Error().Err(err)
		}
	}
	s.ll.Info().Int("releases_loaded", len(releasesIn.Releases)).Msg("database loaded")
	return nil
}

// ReloadDatabase reloads the database from the file if it has changed
func (s *srv) ReloadDatabase() error {
	// Check if file has been modified
	stat, err := os.Stat(s.dbFile)
	if err != nil {
		s.ll.Error().Err(err).Str("file", s.dbFile).Msg("error checking file stat")
		return err
	}

	// If file hasn't changed, skip reload
	if !stat.ModTime().After(s.lastMod) {
		return nil
	}

	s.ll.Info().Time("old_mod_time", s.lastMod).Time("new_mod_time", stat.ModTime()).Msg("file changed, reloading database")

	// Read the file
	data, err := os.ReadFile(s.dbFile)
	if err != nil {
		s.ll.Error().Err(err).Str("file", s.dbFile).Msg("error reading database file")
		return err
	}

	// Load the new data
	if err := s.loadDatabase(data); err != nil {
		s.ll.Error().Err(err).Msg("error loading new database")
		return err
	}

	// Update last modified time
	s.lastMod = stat.ModTime()
	s.ll.Info().Msg("database reloaded successfully")
	return nil
}

// startFileWatcher starts a background goroutine to watch for file changes
func (s *srv) startFileWatcher(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second) // Check every 30 seconds
	go func() {
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				if err := s.ReloadDatabase(); err != nil {
					s.ll.Error().Err(err).Msg("error during automatic database reload")
				}
			case <-ctx.Done():
				s.ll.Info().Msg("file watcher stopping")
				return
			}
		}
	}()
	s.ll.Info().Msg("file watcher started")
}

// Run is a blocking function to run the server in an errgroup
func (s *srv) Run(ctx context.Context) error {
	// Start file watcher
	s.startFileWatcher(ctx)

	// start a new echo server
	e := echo.New()

	// register endpoints
	e.GET("/v1/releases", s.queryHandler)
	e.GET("/v1/ready", s.readyHandler)
	e.GET("/v1/health", s.healthHandler)
	e.POST("/v1/reload", s.reloadHandler) // Manual reload endpoint

	// Create a server so we have a shutdown method
	server := &http.Server{
		Addr:    fmt.Sprintf(":%d", 8089),
		Handler: e,
	}

	// Background the server
	go func() {
		s.ll.Info().Msg("server listening on port 8089")
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			// something happened in the server, log the error and signal a fatal stop
			s.ll.Error().Err(err).Msg("early exit from server")
			close(s.closeChan)
		}
	}()

	// block waiting for context cancel or fatal server error
	for {
		select {
		case <-ctx.Done():
			s.ll.Info().Msg("api exiting")
			server.Shutdown(context.Background())
			return nil
		case <-s.closeChan:
			return errors.New("fatal http server error")
		}
	}
}

// queryHandler responds to queries
func (s *srv) queryHandler(c echo.Context) error {
	// TODO: the db does some sanity checking, but there should be some input validation here
	query := &db.Release{
		Container:      c.QueryParam("container"),
		ReleaseChannel: c.QueryParam("releaseChannel"),
	}
	resp := s.db.Query(query)
	if len(resp) > 0 {
		return c.JSON(http.StatusOK, resp)
	}
	return c.JSON(http.StatusNotFound, resp)
}

func (s *srv) readyHandler(c echo.Context) error {
	return c.JSON(http.StatusOK, "{200: ready}")
}

func (s *srv) healthHandler(c echo.Context) error {
	return c.JSON(http.StatusOK, "{200: healthy}")
}

// reloadHandler manually triggers a database reload
func (s *srv) reloadHandler(c echo.Context) error {
	if err := s.ReloadDatabase(); err != nil {
		s.ll.Error().Err(err).Msg("manual reload failed")
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}
	return c.JSON(http.StatusOK, map[string]string{"status": "reloaded"})
}

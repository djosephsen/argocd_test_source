package main

import (
	"context"
	"fmt"
	"io"
	"os"

	"github.com/myprizepicks/releasechannels-server-poc/internal/server"
	"github.com/rs/zerolog"
	"golang.org/x/sync/errgroup"
)

const inFile = "db/db.json"

// Version is set at build time via ldflags
var Version = "dev"

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	zerolog.SetGlobalLevel(zerolog.DebugLevel)
	gl := zerolog.New(os.Stderr).With().Timestamp().Logger()
	ll := gl.With().Str("package", "main").Logger()

	// Log the version on startup
	ll.Info().Str("version", Version).Msg("starting release channels server")

	eg, ctx := errgroup.WithContext(ctx)

	// Open our db
	db, err := os.Open(inFile)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	defer db.Close()
	ll.Debug().Msg("db file opened")

	// read in the data
	bytes, err := io.ReadAll(db)
	if err != nil {
		ll.Error().Err(err).Msg("error starting server")
		os.Exit(2)
	}

	// create the server
	srv, err := server.New(bytes, inFile, &gl)
	if err != nil {
		ll.Error().Err(err).Msg("error starting server")
		os.Exit(2)
	}

	// start the server
	eg.Go(func() error {
		return srv.Run(ctx)
	})

	eg.Wait()
}

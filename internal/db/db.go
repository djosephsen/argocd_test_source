package db

import (
	"fmt"

	"github.com/rs/zerolog"
)

// Store is the interface for a releasechan api data-store
type Store interface {
	Query(r *Release) Releases
	Write(r *Release) error
}

// Release implements the formal definition of a software release
type Release struct {
	Container      string `json:"container"`
	ImagePath      string `json:"imagePath"`
	ReleaseChannel string `json:"releaseChannel"`
}

// ToKey returns a map-comparable struct-key from a given Release
func (r *Release) ToKey() ReleaseKey {
	return ReleaseKey{
		Container:      r.Container,
		ReleaseChannel: r.ReleaseChannel,
	}
}

// Releases is a list-context Release
type Releases []*Release

// ReleaseKey is a compariable struct-key for use in queries
type ReleaseKey struct {
	Container      string
	ReleaseChannel string
}

// String implements stringer on releasekeys
func (rk *ReleaseKey) String() string {
	return fmt.Sprintf("%s/%s", rk.Container, rk.ReleaseChannel)
}

// inMem Implements Store in-memory
type inMem struct {
	all         Releases
	byChannel   map[string]Releases
	byContainer map[string]Releases
	byBoth      map[ReleaseKey]*Release
	ll          *zerolog.Logger
}

// NewInMemoryStore is a constructor for an in-memory Store
func NewInMemoryStore(gl *zerolog.Logger) Store {
	ll := gl.With().Str("package", "db").Logger()
	return &inMem{
		all:         Releases{},
		byChannel:   make(map[string]Releases),
		byContainer: make(map[string]Releases),
		byBoth:      make(map[ReleaseKey]*Release),
		ll:          &ll,
	}
}

// inMem implements store
var _ Store = &inMem{}

// Query searches the Store for matching releases
func (im *inMem) Query(r *Release) Releases {
	im.ll.Info().Str("container", r.Container).Str("releaseChannel", r.ReleaseChannel).Msg("New Query")

	// first check by release key
	if r.Container != "" && r.ReleaseChannel != "" {
		if out, ok := im.byBoth[r.ToKey()]; ok {
			return Releases{out}
		}
		im.ll.Info().Msgf("empty result in search byBoth for %s", r.ToKey())
		return Releases{}
	}

	// then check by container
	if r.Container != "" {
		if out, ok := im.byContainer[r.Container]; ok {
			return out
		}
		im.ll.Info().Msgf("empty result in search by container for %s", r.Container)
		return Releases{}
	}

	// finally check by channel
	if r.ReleaseChannel != "" {
		if out, ok := im.byChannel[r.ReleaseChannel]; ok {
			return out
		}
		im.ll.Info().Msgf("empty result in search by release channel for %s", r.ReleaseChannel)
		return Releases{}
	}
	im.ll.Info().Msg("global message store dump")
	return im.all
}

// Write adds new releases to the Store
func (im *inMem) Write(r *Release) error {
	im.ll.Debug().Str("container", r.Container).Str("release_channel", r.ReleaseChannel).Str("image_path", r.ImagePath).Msg("new entry")
	// sanity check the input
	if r.Container == "" {
		return fmt.Errorf("`container` not set on write for %s", r)
	}
	if r.ReleaseChannel == "" {
		return fmt.Errorf("`releaseChannel` not set on write for %s", r)
	}
	if r.ImagePath == "" {
		return fmt.Errorf("`image_path` not set on write for %s", r)
	}

	// append the all store
	im.all = append(im.all, r)

	// append the container store
	im.byContainer[r.Container] = append(im.byContainer[r.Container], r)

	// append the release-channel store
	im.byChannel[r.ReleaseChannel] = append(im.byChannel[r.ReleaseChannel], r)

	// append the both store
	im.byBoth[r.ToKey()] = r

	return nil
}

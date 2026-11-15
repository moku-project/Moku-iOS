// Package backend is the native binding surface for Moku's embedded Go core.
// It wraps Tsunagu's upstream embedded package, the same API Moku-Android uses.
package backend

import (
	"errors"
	"net"

	"tsunagu/backend/embedded"
)

// errNotPorted marks iOS features that ran on the old Tsunagu fork and have
// not been rebuilt on upstream Tsunagu yet. They fail loudly instead of
// pretending to work.
var errNotPorted = errors.New("not available yet on upstream Tsunagu")

// Service keeps the Swift API stable while the core underneath changes.
// Tsunagu's embedded core is one per process, so every Service shares it.
type Service struct{}

func NewService() *Service { return &Service{} }

// iOS's JVM loads extension JARs; it cannot load APKs.
func init() { embedded.SetPreferAPK(false) }

func (s *Service) Start(dataDirectory string) error {
	return errors.New("the iOS core needs an extension host: use StartDeferredSandbox or StartWithSandbox")
}

func (s *Service) StartWithSandbox(dataDirectory, address, token string) error {
	if err := checkHost(address); err != nil {
		return err
	}
	return embedded.Start(dataDirectory, address, token)
}

// StartDeferredSandbox starts the core before the JVM is up; call AttachSandbox once it is.
func (s *Service) StartDeferredSandbox(dataDirectory string) error {
	return embedded.Start(dataDirectory, "", "")
}

func (s *Service) AttachSandbox(address, token string) error {
	if err := checkHost(address); err != nil {
		return err
	}
	return embedded.AttachSandbox(address, token)
}

// checkHost only allows the app's own JVM on IPv4 loopback, so the host
// token is never sent off the device.
func checkHost(address string) error {
	host, port, err := net.SplitHostPort(address)
	if err != nil || port == "" || port == "0" {
		return errors.New("extension host address must be 127.0.0.1:<port>")
	}
	if host != "127.0.0.1" {
		return errors.New("extension host must be on 127.0.0.1")
	}
	return nil
}

func (s *Service) Stop() error         { return embedded.Stop() }
func (s *Service) BaseURL() string     { return embedded.BaseURL() }
func (s *Service) AccessToken() string { return embedded.APIToken() }

// VideoObserver carries cancellation and measured progress across the native boundary.
type VideoObserver interface {
	Cancelled() bool
	Progress(fraction float64, bytes int64, bytesPerSecond float64)
}
type VideoEngine interface {
	Process(url, headersJSON, outputPath string, observer VideoObserver) error
}

// SetVideoEngine has the core download episodes with the app's in-process
// FFmpeg (TSVideoEngine): iOS cannot run ffmpeg as a program. Call before Start.
func (s *Service) SetVideoEngine(engine VideoEngine) error {
	if engine == nil {
		return errors.New("native video engine is required")
	}
	embedded.SetVideoEngine(engineAdapter{engine})
	return nil
}

type engineAdapter struct{ engine VideoEngine }

func (a engineAdapter) Process(url, headersJSON, outputPath string, observer embedded.VideoObserver) error {
	return a.engine.Process(url, headersJSON, outputPath, observer)
}

func (s *Service) BeginBrowserVerification(extensionID, url string) (string, error) {
	return "", errNotPorted
}
func (s *Service) BrowserCookies(sessionID string) (string, error) { return "", errNotPorted }
func (s *Service) CompleteBrowserVerification(sessionID, stateJSON string) error {
	return errNotPorted
}
func (s *Service) CancelBrowserVerification(sessionID string) {}

func (s *Service) ImportLocalFile(source, kind, series, chapter, name string) error {
	return errNotPorted
}

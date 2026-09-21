// Package backend is the native binding surface for Moku's embedded Go core.
package backend

import (
	"errors"
	"tsunagu/backend/mobile"
)

// Service hides upstream implementation types from the generated Swift API.
type Service struct{ core *mobile.Backend }

func NewService() *Service                          { return &Service{core: mobile.NewBackend()} }
func (s *Service) Start(dataDirectory string) error { return s.core.Start(dataDirectory) }
func (s *Service) Stop() error                      { return s.core.Stop() }
func (s *Service) BaseURL() string                  { return s.core.BaseURL() }
func (s *Service) AccessToken() string              { return s.core.AccessToken() }
func (s *Service) Status() string                   { return s.core.Status() }

func (s *Service) StartWithSandbox(dataDirectory, address, token string) error {
	return s.core.StartWithSandbox(dataDirectory, address, token)
}

// VideoObserver carries cancellation and measured progress across the native boundary.
type VideoObserver interface {
	Cancelled() bool
	Progress(fraction float64, bytes int64, bytesPerSecond float64)
}
type VideoEngine interface {
	Process(url, headersJSON, outputPath string, observer VideoObserver) error
}
type engineAdapter struct{ engine VideoEngine }

func (a engineAdapter) Process(url, headers, path string, observer mobile.VideoObserver) error {
	return a.engine.Process(url, headers, path, observer)
}
func (s *Service) SetVideoEngine(engine VideoEngine) error {
	if engine == nil {
		return errors.New("native video engine is required")
	}
	return s.core.SetVideoEngine(engineAdapter{engine})
}

func (s *Service) BeginBrowserVerification(extensionID, url string) (string, error) {
	return s.core.BeginBrowserVerification(extensionID, url)
}
func (s *Service) BrowserCookies(sessionID string) (string, error) {
	return s.core.BrowserCookies(sessionID)
}
func (s *Service) CompleteBrowserVerification(sessionID, stateJSON string) error {
	return s.core.CompleteBrowserVerification(sessionID, stateJSON)
}
func (s *Service) CancelBrowserVerification(sessionID string) {
	s.core.CancelBrowserVerification(sessionID)
}
func (s *Service) ImportLocalFile(source, kind, series, chapter, name string) error {
	return s.core.ImportLocalFile(source, kind, series, chapter, name)
}

func (s *Service) StartDeferredSandbox(dataDirectory string) error {
	return s.core.StartDeferredSandbox(dataDirectory)
}
func (s *Service) AttachSandbox(address, token string) error {
	return s.core.AttachSandbox(address, token)
}

// Package backend is the gomobile binding over Tsunagu's embedded package, the API Moku-Android also uses.
package backend

import (
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"

	"tsunagu/backend/embedded"
)

// Service keeps the Swift API stable; every Service shares Tsunagu's one-per-process core.
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

// checkHost only allows the app's own JVM on IPv4 loopback, so the host token never leaves the device.
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

// SetVideoEngine routes episode downloads through the in-process FFmpeg, since iOS can't spawn ffmpeg; call before Start.
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

// Browser verification: see SourceVerificationBrowser.swift.
func (s *Service) BeginBrowserVerification(extensionID, url string) (string, error) {
	return embedded.BeginBrowserVerification(extensionID, url)
}
func (s *Service) BrowserCookies(sessionID string) (string, error) {
	return embedded.BrowserCookies(sessionID)
}
func (s *Service) CompleteBrowserVerification(sessionID, stateJSON string) error {
	return embedded.CompleteBrowserVerification(sessionID, stateJSON)
}
func (s *Service) CancelBrowserVerification(sessionID string) {
	embedded.CancelBrowserVerification(sessionID)
}

// ImportLocalFile copies a picked file into <dir>/<kind>/<series>/<chapter>/<name> (a chapter CBZ: <dir>/manga/<series>/<name>), never overwriting.
func (s *Service) ImportLocalFile(source, kind, series, chapter, name string) error {
	if kind != "manga" && kind != "anime" && kind != "novels" {
		return errors.New("invalid local content type")
	}
	for _, part := range []string{series, chapter, name} {
		if part == "" || part == "." || part == ".." || filepath.Base(part) != part || strings.ContainsAny(part, `\/`) {
			return errors.New("invalid import name")
		}
	}
	root := embedded.LocalSourceDir()
	if root == "" {
		return errors.New("tsunagu is not running")
	}
	info, err := os.Lstat(source)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return errors.New("only regular files can be imported")
	}
	directory := filepath.Join(root, kind, series)
	ext := strings.ToLower(filepath.Ext(name))
	if kind != "manga" || (ext != ".cbz" && ext != ".zip") {
		directory = filepath.Join(directory, chapter)
	}
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return err
	}
	canonical, err := filepath.EvalSymlinks(directory)
	if err != nil {
		return err
	}
	base, err := filepath.EvalSymlinks(root)
	if err != nil {
		return err
	}
	if rel, err := filepath.Rel(base, canonical); err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return errors.New("import destination escapes the local folder")
	}
	destination := filepath.Join(canonical, name)
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		if os.IsExist(err) {
			return errors.New("a file with this name already exists")
		}
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		os.Remove(destination)
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(destination)
		return err
	}
	return nil
}

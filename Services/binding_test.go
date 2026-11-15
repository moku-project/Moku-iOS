package backend

import (
	"os"
	"path/filepath"
	"testing"

	"tsunagu/backend/embedded"
)

func TestImportLocalFile(t *testing.T) {
	s := NewService()
	if err := s.StartDeferredSandbox(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	defer s.Stop()
	root := embedded.LocalSourceDir()

	src := filepath.Join(t.TempDir(), "picked.cbz")
	if err := os.WriteFile(src, []byte("zip"), 0o600); err != nil {
		t.Fatal(err)
	}

	// A CBZ holds a whole chapter, so it sits directly in the series folder.
	if err := s.ImportLocalFile(src, "manga", "Series", "Chapter 1", "Chapter 1.cbz"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "manga", "Series", "Chapter 1.cbz")); err != nil {
		t.Fatal(err)
	}
	// Anything else goes in a chapter folder.
	if err := s.ImportLocalFile(src, "novels", "Book", "Part 1", "part.epub"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "novels", "Book", "Part 1", "part.epub")); err != nil {
		t.Fatal(err)
	}

	if err := s.ImportLocalFile(src, "manga", "Series", "Chapter 1", "Chapter 1.cbz"); err == nil {
		t.Fatal("overwrote an existing file")
	}
	for _, bad := range [][3]string{
		{"..", "c", "f.cbz"}, {"s", "../c", "f.epub"}, {"s", "c", "../f.cbz"}, {"s/x", "c", "f.cbz"}, {"s", "c", ""},
	} {
		if err := s.ImportLocalFile(src, "manga", bad[0], bad[1], bad[2]); err == nil {
			t.Errorf("accepted names %q", bad)
		}
	}
	if err := s.ImportLocalFile(src, "games", "s", "c", "f.cbz"); err == nil {
		t.Error("accepted an unknown kind")
	}
	if err := s.ImportLocalFile(filepath.Dir(src), "manga", "s", "c", "f.cbz"); err == nil {
		t.Error("imported a directory")
	}
}

func TestAttachOnlyAllowsLoopback(t *testing.T) {
	s := NewService()
	for _, addr := range []string{"example.com:1", "10.0.0.2:80", "127.0.0.1", "127.0.0.1:0", ""} {
		if err := s.AttachSandbox(addr, "t"); err == nil {
			t.Errorf("AttachSandbox(%q) succeeded", addr)
		}
	}
}

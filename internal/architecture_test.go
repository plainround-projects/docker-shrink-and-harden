// Package internal_test enforces the dependency rule: domain imports nothing of ours; application imports domain;
// infrastructure and interfaces import the layers below; nothing imports interfaces.
package internal_test

import (
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"strings"
	"testing"
)

const module = "example.com/svc/internal/"

// allowed lists, for each layer, the layers its non-test code may import.
var allowed = map[string][]string{
	"domain":         {},
	"application":    {"domain"},
	"infrastructure": {"domain", "application"},
	"interfaces":     {"domain", "application", "infrastructure"},
}

func TestLayersOnlyImportDownward(t *testing.T) {
	for layer, permitted := range allowed {
		err := filepath.WalkDir(layer, func(path string, entry fs.DirEntry, err error) error {
			if err != nil || entry.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
				return err
			}
			file, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
			if err != nil {
				return err
			}
			for _, spec := range file.Imports {
				target := strings.Trim(spec.Path.Value, `"`)
				if !strings.HasPrefix(target, module) {
					continue
				}
				imported := strings.SplitN(strings.TrimPrefix(target, module), "/", 2)[0]
				if imported != layer && !contains(permitted, imported) {
					t.Errorf("%s (layer %s) imports %s: the layer %q is not allowed", path, layer, target, imported)
				}
			}
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}

func TestDomainAndApplicationUseOnlyTheStandardLibraryAndEachOther(t *testing.T) {
	for _, layer := range []string{"domain", "application"} {
		_ = filepath.WalkDir(layer, func(path string, entry fs.DirEntry, err error) error {
			if err != nil || entry.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
				return err
			}
			file, _ := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
			for _, spec := range file.Imports {
				target := strings.Trim(spec.Path.Value, `"`)
				if strings.Contains(strings.SplitN(target, "/", 2)[0], ".") && !strings.HasPrefix(target, module) {
					t.Errorf("%s imports third-party package %s", path, target)
				}
			}
			return nil
		})
	}
}

func contains(list []string, item string) bool {
	for _, candidate := range list {
		if candidate == item {
			return true
		}
	}
	return false
}

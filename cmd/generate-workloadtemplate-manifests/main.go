// Copyright 2025 Sudo Sweden AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"cuelang.org/go/cue"
	"cuelang.org/go/cue/cuecontext"
	"cuelang.org/go/cue/format"
	"cuelang.org/go/cue/load"

	"cuelang.org/go/cue/parser"
	"github.com/spf13/pflag"
	dockyardsv1 "github.com/sudoswedenab/dockyards-backend/api/v1alpha3"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	kustomize "sigs.k8s.io/kustomize/api/types"
	"sigs.k8s.io/yaml"
)

type generator struct {
	outpath   string
	resources []string
}

var re *regexp.Regexp
var templatePath string

func (g *generator) walkDir(path string, dirEntry fs.DirEntry, err error) error {
	if err != nil {
		return err
	}

	if dirEntry.IsDir() {
		return nil
	}

	base := filepath.Base(path)

	if strings.HasSuffix(base, "testdata") {
		return nil
	}

	name := strings.TrimSuffix(base, ".cue")

	fmt.Println(base, name)

	file, err := parser.ParseFile(path, nil, parser.AllErrors, parser.DeclarationErrors, parser.ParseComments)
	if err != nil {
		return fmt.Errorf("could not parse file '%s': %w", path, err)
	}

	if templatePath == "" {
		cwd, err := os.Getwd()
		if err != nil {
			return fmt.Errorf("could not get cwd: %w", err)
		}
		templatePath = filepath.Join(cwd, "template.cue")
	}

	cuectx := cuecontext.New()

	instances := load.Instances([]string{}, &load.Config{
		Package: "template",
		Overlay: map[string]load.Source{
			templatePath: load.FromFile(file),
		},
	})

	if len(instances) != 1 {
		return fmt.Errorf("expected values to be of length 1, but found %d", len(instances))
	}

	instance := instances[0]

	value := cuectx.BuildInstance(instance)
	err = value.Err()
	if err != nil {
		return fmt.Errorf("could not build instances for file '%s': %w", path, err)
	}

	syntaxTree := value.Syntax(cue.InlineImports(true))

	b, err := format.Node(syntaxTree, format.TabIndent(false), format.UseSpaces(2), format.Simplify())
	if err != nil {
		return fmt.Errorf("could not format node: %w", err)
	}

	gvk := schema.GroupVersionKind{
		Group:   dockyardsv1.GroupVersion.Group,
		Version: dockyardsv1.GroupVersion.Version,
		Kind:    dockyardsv1.WorkloadTemplateKind,
	}

	u := unstructured.Unstructured{}
	u.SetGroupVersionKind(gvk)
	u.SetName(name)

	_ = unstructured.SetNestedField(u.Object, string(b), "spec", "source")
	_ = unstructured.SetNestedField(u.Object, string(dockyardsv1.WorkloadTemplateTypeCue), "spec", "type")

	b, err = yaml.Marshal(&u)
	if err != nil {
		return err
	}

	if re == nil {
		re = regexp.MustCompile(`[^\w]`)
	}

	clean := re.ReplaceAllString(name, "")

	resource := fmt.Sprintf("workloadtemplate_%s.yaml", clean)

	output := filepath.Join(g.outpath, resource)

	err = os.WriteFile(output, b, 0o666)
	if err != nil {
		return err
	}

	g.resources = append(g.resources, resource)

	return nil
}

func main() {
	var inpath string
	var outpath string
	pflag.StringVar(&inpath, "root", "templates", "root")
	pflag.StringVar(&outpath, "outpath", "manifests", "outpath")
	pflag.Parse()

	g := generator{
		outpath: outpath,
	}

	err := os.MkdirAll(outpath, 0o755)
	if err != nil {
		panic(err)
	}

	err = filepath.WalkDir(inpath, g.walkDir)
	if err != nil {
		panic(err)
	}

	kustomization := kustomize.Kustomization{
		TypeMeta: kustomize.TypeMeta{
			APIVersion: kustomize.KustomizationVersion,
			Kind:       kustomize.KustomizationKind,
		},
		Resources: g.resources,
	}

	b, err := yaml.Marshal(&kustomization)
	if err != nil {
		panic(err)
	}

	filename := filepath.Join(outpath, "kustomization.yaml")

	err = os.WriteFile(filename, b, 0o666)
	if err != nil {
		panic(err)
	}
}

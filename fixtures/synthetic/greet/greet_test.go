package greet

import "testing"

func TestHello(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"empty name defaults", "", "Hello, world!"},
		{"simple name", "Hestia", "Hello, Hestia!"},
		{"punctuation in name", "Ada L.", "Hello, Ada L.!"},
	}
	for _, tc := range cases {
		if got := Hello(tc.in); got != tc.want {
			t.Errorf("%s: Hello(%q) = %q, want %q", tc.name, tc.in, got, tc.want)
		}
	}
}

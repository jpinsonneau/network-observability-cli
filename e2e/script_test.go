//go:build e2e

package e2e

import (
	"os"
	"path"
	"testing"

	"github.com/sirupsen/logrus"
	"github.com/stretchr/testify/assert"
)

var (
	slog = logrus.WithField("component", "script_test")
)

func TestHelpCommand(t *testing.T) {
	t.Run("help command", func(t *testing.T) {
		output, err := RunCommand(slog, "oc-netobserv", "help")
		assert.Nil(t, err)

		err = os.WriteFile(path.Join("output", StartupDate+"-helpOutput"), output, 0666)
		assert.Nil(t, err)

		str := string(output)
		assert.NotEmpty(t, str)
		// ensure help display overall description
		assert.Contains(t, str, "Netobserv allows you to capture flow, packets and metrics from your cluster.")
		assert.Contains(t, str, "Find more information at: https://github.com/netobserv/network-observability-cli/")
		// ensure help to display proper options
		assert.Contains(t, str, "Syntax: netobserv [flows|packets|metrics|follow|stop|copy|cleanup|version] [options]")
		assert.Contains(t, str, "flows      Capture flows information in JSON format using collector pod.")
		assert.Contains(t, str, "packets    Capture packets information in pcap format using collector pod.")
		assert.Contains(t, str, "metrics    Capture metrics information in Prometheus using a ServiceMonitor (OCP cluster only).")
		assert.Contains(t, str, "follow     Follow collector logs when running in background.")
		assert.Contains(t, str, "stop       Stop collection by removing agent daemonset.")
		assert.Contains(t, str, "copy       Copy collector generated files locally.")
		assert.Contains(t, str, "cleanup    Remove netobserv components and configurations.")
		assert.Contains(t, str, "version    Print software version.")
	})
}

func TestVersionCommand(t *testing.T) {
	t.Run("version command", func(t *testing.T) {
		output, err := RunCommand(slog, "oc-netobserv", "version")
		assert.Nil(t, err)

		err = os.WriteFile(path.Join("output", StartupDate+"-versionOutput"), output, 0666)
		assert.Nil(t, err)

		str := string(output)
		assert.NotEmpty(t, str)
		// ensure version display test
		assert.Contains(t, str, "Netobserv CLI version test")
	})
}

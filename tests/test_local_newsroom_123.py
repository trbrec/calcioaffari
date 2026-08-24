from pathlib import Path
import json
import re
import unittest


ROOT = Path(__file__).resolve().parents[1] / "companion" / "calcioaffari-local-agent"


def read(name: str) -> str:
    return (ROOT / name).read_text(encoding="utf-8-sig")


class LocalNewsroom124Tests(unittest.TestCase):
    def test_release_version_is_coherent(self):
        manifest = json.loads(read("version.json"))
        self.assertEqual(manifest["version"], "1.2.4")
        for name in (
            "agent.ps1", "dashboard.ps1", "diagnose.ps1", "heartbeat.ps1",
            "install.ps1", "repair.ps1", "setup-gui.ps1", "upgrade.ps1",
        ):
            self.assertIn('$AgentVersion = "1.2.4"', read(name), name)
        self.assertIn('#define AppVersion "1.2.4"', read("installer.iss"))

    def test_installer_layout_can_pair_without_unversioned_payloads(self):
        install = read("install.ps1")
        self.assertIn('Join-Path $PSScriptRoot "agent-$AgentVersion.ps1"', install)
        self.assertIn('Join-Path $PSScriptRoot "version-$AgentVersion.json"', install)
        self.assertIn("never copy a file onto itself", install)

    def test_named_completion_rejection_is_remembered_terminally(self):
        agent = read("agent.ps1")
        completion_catch = agent.split('WordPress ha rifiutato il risultato del job', 1)[1]
        self.assertIn("$serverCode = Get-CalcioAffariServerErrorCode $_", agent)
        self.assertIn("$script:TerminalJobs[[string]$job.id]", completion_catch)
        self.assertIn("respinto definitivamente da WordPress", completion_catch)

    def test_unacknowledged_terminal_failure_stops_the_agent_loop(self):
        agent = read("agent.ps1")
        self.assertIn("CA_TERMINAL_FAIL_NOT_ACKNOWLEDGED", agent)
        self.assertIn("Elaborazione sospesa per evitare un ciclo continuo", agent)

    def test_requeued_terminal_job_stops_before_ollama(self):
        agent = read("agent.ps1")
        self.assertIn("function Assert-CalcioAffariJobNotRequeued", agent)
        cycle = agent.split("function Invoke-AgentCycle", 1)[1]
        self.assertLess(
            cycle.index("Assert-CalcioAffariJobNotRequeued $job"),
            cycle.index("Invoke-Ollama $Runtime.Config $job"),
        )
        self.assertIn("CA_SERVER_REQUEUED_TERMINAL", agent)

    def test_diagnostics_include_heartbeat_and_all_version_manifests(self):
        for name in ("dashboard.ps1", "setup-gui.ps1"):
            source = read(name)
            self.assertIn('"heartbeat.log"', source)
            self.assertIn('Filter "version-*.json"', source)

    def test_pause_is_persistent_and_stops_every_calcioaffari_runtime(self):
        common = read("common.ps1")
        dashboard = read("dashboard.ps1")
        heartbeat = read("heartbeat.ps1")
        agent = read("agent.ps1")
        self.assertIn("function Suspend-CalcioAffariAutomation", common)
        self.assertIn('"agent-paused.txt"', common)
        self.assertIn("Set-CalcioAffariScheduledTaskEnabled -Name $TaskName -Enabled $false", common)
        self.assertIn("Set-CalcioAffariScheduledTaskEnabled -Name $WatchdogTaskName -Enabled $false", common)
        self.assertIn("Stop-CalcioAffariRuntimeProcesses", common)
        self.assertIn("Stop-CalcioAffariModel", common)
        self.assertIn('@("stop", $Model)', common)
        self.assertIn('$pauseButton.Text = "PAUSA"', dashboard)
        self.assertIn("$form.Add_FormClosing", dashboard)
        self.assertIn("Suspend-FromDashboard", dashboard)
        self.assertIn('"agent-paused.txt"', dashboard)
        self.assertIn('"agent-paused.txt"', read("setup-gui.ps1"))
        self.assertIn("if (Test-Path $UserPausePath) { exit 0 }", heartbeat)
        self.assertIn("if (Test-Path $UserPausePath)", agent)

    def test_balanced_profile_releases_model_quickly_and_caps_threads(self):
        common = read("common.ps1")
        self.assertIn('KeepAlive = "2m"; NumThread = 6', common)
        self.assertIn('KeepAlive = "0"; NumThread = 4', common)


if __name__ == "__main__":
    unittest.main()

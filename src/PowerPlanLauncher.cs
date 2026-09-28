using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

internal static class PowerPlanLauncher
{
    // Quote individual Windows process arguments; no shell or command file.
    private static string Quote(string value)
    {
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            result.Append('\\', c == '"' ? slashes * 2 + 1 : slashes);
            result.Append(c);
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string directory = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            string script = Path.Combine(directory, "PowerPlanManager.ps1");
            string core = Path.Combine(directory, "PowerPlan.Core.ps1");
            if (!File.Exists(script) || !File.Exists(core) || !File.Exists(Path.Combine(directory, "PowerPlan.UI.ps1")))
                throw new FileNotFoundException("The application package is incomplete. Please extract or download the complete package again.");
            string host = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            StringBuilder command = new StringBuilder("-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File ");
            command.Append(Quote(script));
            foreach (string argument in args) command.Append(' ').Append(Quote(argument));
            ProcessStartInfo start = new ProcessStartInfo(host, command.ToString());
            start.WorkingDirectory = directory;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardError = true;
            start.RedirectStandardOutput = true;
            using (Process process = Process.Start(start))
            {
                var errors = process.StandardError.ReadToEndAsync();
                var output = process.StandardOutput.ReadToEndAsync();
                process.WaitForExit();
                string error = errors.Result;
                string ignoredOutput = output.Result;
                if (process.ExitCode != 0)
                {
                    if (error.Length > 4000) error = error.Substring(0, 4000);
                    MessageBox.Show("Power Plan Manager could not finish.\r\n" + error,
                        "Power Plan Manager 0.3.2 - startup error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Power Plan Manager 0.3.2 - launcher error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}

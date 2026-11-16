using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Threading;
using System.Windows.Forms;

namespace StonexLauncher
{
    static class Program
    {
        static bool IsPortInUse(int port)
        {
            try
            {
                using (var client = new TcpClient())
                {
                    var result = client.BeginConnect("127.0.0.1", port, null, null);
                    bool success = result.AsyncWaitHandle.WaitOne(300);
                    if (success)
                    {
                        client.EndConnect(result);
                        return true;
                    }
                    return false;
                }
            }
            catch
            {
                return false;
            }
        }

        [STAThread]
        static void Main()
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string nativeExe = Path.Combine(localAppData, "NTJ_ERP", "stonex_erp.exe");
            if (File.Exists(nativeExe))
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = nativeExe;
                psi.WorkingDirectory = Path.Combine(localAppData, "NTJ_ERP");
                psi.UseShellExecute = true;
                try
                {
                    Process.Start(psi);
                    return;
                }
                catch { }
            }

            int port = 5500;
            string projectDir = @"C:\Users\USER\OneDrive\Desktop\stonex_erp";
            string webDir = Path.Combine(projectDir, "app", "build", "web");

            if (!Directory.Exists(webDir))
            {
                string localWeb = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app", "build", "web");
                if (Directory.Exists(localWeb))
                {
                    webDir = localWeb;
                }
            }

            if (!IsPortInUse(port) && Directory.Exists(webDir))
            {
                string pythonExe = @"C:\Users\USER\AppData\Local\Programs\Python\Python315\python.exe";
                if (!File.Exists(pythonExe))
                {
                    string candidate = Path.Combine(localAppData, "Programs", "Python", "Python315", "python.exe");
                    if (File.Exists(candidate)) pythonExe = candidate;
                    else pythonExe = "python.exe";
                }

                ProcessStartInfo srv = new ProcessStartInfo
                {
                    FileName = pythonExe,
                    Arguments = "-m http.server " + port + " --directory \"" + webDir + "\"",
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    WindowStyle = ProcessWindowStyle.Hidden
                };

                try
                {
                    Process.Start(srv);
                }
                catch { }

                for (int i = 0; i < 25; i++)
                {
                    if (IsPortInUse(port)) break;
                    Thread.Sleep(150);
                }
            }

            string url = "http://localhost:" + port;
            string chrome = @"C:\Program Files\Google\Chrome\Application\chrome.exe";
            string edge = @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe";

            ProcessStartInfo app = new ProcessStartInfo();
            app.UseShellExecute = true;
            if (File.Exists(chrome))
            {
                app.FileName = chrome;
                app.Arguments = "--app=" + url + " --window-size=1366,850";
            }
            else if (File.Exists(edge))
            {
                app.FileName = edge;
                app.Arguments = "--app=" + url + " --window-size=1366,850";
            }
            else
            {
                app.FileName = url;
            }

            try
            {
                Process.Start(app);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Dasturni ochishda xatolik: " + ex.Message, "Stonex ERP", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}

using System;
using System.IO;
using System.IO.Compression;
using System.Diagnostics;
using System.Reflection;
using System.Windows.Forms;

namespace NTJInstaller
{
    class Program
    {
        [STAThread]
        static void Main()
        {
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string installDir = Path.Combine(localAppData, "NTJ_ERP");
                string exeTarget = Path.Combine(installDir, "stonex_erp.exe");

                Assembly asm = Assembly.GetExecutingAssembly();
                using (Stream stream = asm.GetManifestResourceStream("payload.zip"))
                {
                    if (stream != null)
                    {
                        if (!Directory.Exists(installDir))
                        {
                            Directory.CreateDirectory(installDir);
                        }
                        
                        using (ZipArchive archive = new ZipArchive(stream))
                        {
                            foreach (ZipArchiveEntry entry in archive.Entries)
                            {
                                string destinationPath = Path.Combine(installDir, entry.FullName);
                                if (string.IsNullOrEmpty(entry.Name))
                                {
                                    Directory.CreateDirectory(destinationPath);
                                }
                                else
                                {
                                    string dir = Path.GetDirectoryName(destinationPath);
                                    if (!Directory.Exists(dir))
                                    {
                                        Directory.CreateDirectory(dir);
                                    }
                                    try
                                    {
                                        entry.ExtractToFile(destinationPath, true);
                                    }
                                    catch
                                    {
                                        // Ignore if file is in use
                                    }
                                }
                            }
                        }
                    }
                }

                // Desktop yorlig'ini yaratish
                try
                {
                    string desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
                    string shortcutPath = Path.Combine(desktop, "NTJ_ERP.lnk");
                    Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                    if (shellType != null)
                    {
                        dynamic shell = Activator.CreateInstance(shellType);
                        dynamic shortcut = shell.CreateShortcut(shortcutPath);
                        shortcut.TargetPath = exeTarget;
                        shortcut.WorkingDirectory = installDir;
                        shortcut.Description = "NTJ — Namuna Tosh Jilo ERP";
                        shortcut.IconLocation = exeTarget + ",0";
                        shortcut.Save();
                    }
                }
                catch {}

                // Dasturni ishga tushirish
                if (File.Exists(exeTarget))
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = exeTarget;
                    psi.WorkingDirectory = installDir;
                    Process.Start(psi);
                }
                else
                {
                    MessageBox.Show("Dastur fayllari topilmadi: " + exeTarget, "NTJ ERP", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("O‘rnatishda xatolik: " + ex.Message, "NTJ ERP", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}

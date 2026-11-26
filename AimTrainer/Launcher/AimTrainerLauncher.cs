// AimTrainer.exe - installs and starts the Aim Trainer for Unreal Tournament (OldUnreal 469 patches).
//
// The Aim Trainer's four files are inside this exe. Running it:
//   1. finds the UT folder (next to the exe, the folder used last time, the
//      registry, Steam / GOG, common folders, or asks),
//   2. copies AimTrainer.u, AimTrainer.int, AimTrainerMoves.ini (System) and
//      DM-AimRange.unr (Maps) there - only these files, nothing else is touched,
//   3. starts UT in the Aim Trainer on DM-AimRange.
//
//   AimTrainer.exe                  install / update, then play
//   AimTrainer.exe "D:\Games\UT"    use this UT folder (or drop the folder on the exe)
//   AimTrainer.exe choose           choose the UT folder again (or hold Shift when starting it)
//   AimTrainer.exe install          install / update only
//   AimTrainer.exe uninstall        remove the four files again
//   add "quiet" to install / uninstall without any messages (for scripts)
//
// Built with the .NET Framework's own C# compiler (AimTrainer\Tools\make_release.py).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Aim Trainer for Unreal Tournament")]
[assembly: AssemblyDescription("Installs and starts the Aim Trainer for UT99 (OldUnreal 469)")]
[assembly: AssemblyProduct("Aim Trainer")]
[assembly: AssemblyVersion("1.3.0.0")]
[assembly: AssemblyFileVersion("1.3.0.0")]

static class Program
{
    const string Title = "Aim Trainer";
    const string StartUrl = "DM-AimRange?game=AimTrainer.ATGame";
    static bool Quiet;
    static readonly string[,] Files = {
        { "AimTrainer.u", "System" },
        { "AimTrainer.int", "System" },
        { "AimTrainerMoves.ini", "System" },
        { "DM-AimRange.unr", "Maps" },
    };

    [STAThread]
    static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        try
        {
            bool uninstall = false, installOnly = false, choose = false;
            string pathArg = null;
            foreach (string a in args)
            {
                string t = a.Trim().TrimStart('/', '-').ToLowerInvariant();
                if (t == "uninstall") uninstall = true;
                else if (t == "install") installOnly = true;
                else if (t == "quiet") Quiet = true;
                else if (t == "choose" || t == "change") choose = true;
                else pathArg = a;
            }
            // Shift held while starting: choose the UT folder again
            if ((Control.ModifierKeys & Keys.Shift) != 0 && !Quiet)
                choose = true;

            string ut = (choose && pathArg == null) ? AskForUT() : FindUT(pathArg);
            if (ut == null)
                return 1;

            if (uninstall)
            {
                Uninstall(ut);
                return 0;
            }
            while (true)
            {
                DialogResult v = CheckVersion(ut);
                if (v == DialogResult.Yes)
                    break;
                if (v != DialogResult.No)
                    return 1;
                ut = AskForUT();      // No: another folder
                if (ut == null)
                    return 1;
            }
            int changed = Install(ut);
            SaveUT(ut);
            if (installOnly)
            {
                if (!Quiet)
                    MessageBox.Show(changed > 0
                        ? "Aim Trainer installed in\n" + ut
                        : "Aim Trainer is up to date in\n" + ut,
                    Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 0;
            }
            Launch(ut);
            return 0;
        }
        catch (Exception e)
        {
            if (!Quiet)
                MessageBox.Show("Something went wrong:\n\n" + e.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }
    }

    // ---------------------------------------------------------------- finding UT

    static bool IsUT(string dir)
    {
        if (string.IsNullOrEmpty(dir))
            return false;
        try
        {
            return File.Exists(Path.Combine(dir, @"System\UnrealTournament.exe"))
                && File.Exists(Path.Combine(dir, @"System\Botpack.u"));
        }
        catch { return false; }
    }

    // The UT folder for a path that may be the UT folder, its System folder or a file in it.
    static string Normalize(string p)
    {
        if (string.IsNullOrEmpty(p))
            return null;
        try
        {
            p = p.Trim().Trim('"');
            if (File.Exists(p))
                p = Path.GetDirectoryName(p);
            p = Path.GetFullPath(p).TrimEnd('\\');
            if (IsUT(p))
                return p;
            string parent = Path.GetDirectoryName(p);
            if (parent != null && IsUT(parent))
                return parent;
        }
        catch { }
        return null;
    }

    static string SavedPathFile()
    {
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), @"AimTrainerUT\ut_path.txt");
    }

    static void SaveUT(string ut)
    {
        try
        {
            string f = SavedPathFile();
            Directory.CreateDirectory(Path.GetDirectoryName(f));
            File.WriteAllText(f, ut);
        }
        catch { }
    }

    static string FindUT(string pathArg)
    {
        string ut;
        if (pathArg != null)
        {
            ut = Normalize(pathArg);
            if (ut != null)
                return ut;
            if (Quiet)
                return null;
            MessageBox.Show("No Unreal Tournament found in\n" + pathArg, Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return AskForUT();
        }

        // next to the exe (exe put in the UT folder or its System folder)
        ut = Normalize(AppDomain.CurrentDomain.BaseDirectory);
        if (ut != null)
            return ut;

        // the folder used last time
        try
        {
            if (File.Exists(SavedPathFile()))
            {
                ut = Normalize(File.ReadAllText(SavedPathFile()));
                if (ut != null)
                    return ut;
            }
        }
        catch { }

        // somewhere else: confirm the first time
        foreach (string c in Candidates())
        {
            ut = Normalize(c);
            if (ut == null)
                continue;
            DialogResult r = MessageBox.Show(
                "Found Unreal Tournament in\n\n" + ut + "\n\nInstall the Aim Trainer there?\n\n" +
                "(No: choose another folder.)", Title, MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (r == DialogResult.Yes)
                return ut;
            if (r == DialogResult.Cancel)
                return null;
            break;
        }
        return AskForUT();
    }

    static string AskForUT()
    {
        while (true)
        {
            using (FolderBrowserDialog d = new FolderBrowserDialog())
            {
                d.Description = "Choose your Unreal Tournament folder (the one with the System folder in it).";
                d.ShowNewFolderButton = false;
                if (d.ShowDialog() != DialogResult.OK)
                    return null;
                string ut = Normalize(d.SelectedPath);
                if (ut != null)
                    return ut;
                MessageBox.Show("That folder has no System\\UnrealTournament.exe. Choose the Unreal Tournament folder.",
                    Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
    }

    static IEnumerable<string> Candidates()
    {
        List<string> list = new List<string>();
        foreach (RegistryView view in new[] { RegistryView.Registry32, RegistryView.Registry64 })
        {
            AddRegistry(list, RegistryHive.LocalMachine, view, @"SOFTWARE\Unreal Technology\Installed Apps\UnrealTournament", "Folder");
            AddRegistry(list, RegistryHive.LocalMachine, view, @"SOFTWARE\GOG.com\Games\1207658691", "path");
        }
        // Steam libraries
        try
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam"))
            {
                string steam = k == null ? null : k.GetValue("SteamPath") as string;
                if (steam != null)
                {
                    steam = steam.Replace('/', '\\');
                    list.Add(Path.Combine(steam, @"steamapps\common\Unreal Tournament"));
                    string vdf = Path.Combine(steam, @"steamapps\libraryfolders.vdf");
                    if (File.Exists(vdf))
                        foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s+\"([^\"]+)\""))
                            list.Add(Path.Combine(m.Groups[1].Value.Replace(@"\\", @"\"), @"steamapps\common\Unreal Tournament"));
                }
            }
        }
        catch { }
        foreach (DriveInfo drive in DriveInfo.GetDrives())
        {
            if (drive.DriveType != DriveType.Fixed)
                continue;
            string root = drive.RootDirectory.FullName;
            list.Add(Path.Combine(root, "UnrealTournament"));
            list.Add(Path.Combine(root, @"Games\UnrealTournament"));
            list.Add(Path.Combine(root, @"Games\Unreal Tournament"));
            list.Add(Path.Combine(root, @"Program Files (x86)\Unreal Tournament"));
            list.Add(Path.Combine(root, @"Program Files (x86)\GOG Galaxy\Games\Unreal Tournament GOTY"));
            list.Add(Path.Combine(root, @"GOG Games\Unreal Tournament GOTY"));
        }
        return list;
    }

    static void AddRegistry(List<string> list, RegistryHive hive, RegistryView view, string key, string value)
    {
        try
        {
            using (RegistryKey b = RegistryKey.OpenBaseKey(hive, view))
            using (RegistryKey k = b.OpenSubKey(key))
            {
                string v = k == null ? null : k.GetValue(value) as string;
                if (!string.IsNullOrEmpty(v))
                    list.Add(v);
            }
        }
        catch { }
    }

    // ---------------------------------------------------------------- version

    // The game writes its version to its log ("Init: Version: 469"). The trainer
    // is built and tested on 469f, and players report 469b works too; only a
    // game older than 469 (436, 451) gets a warning, since it is untested there.
    // Yes: go on; No: choose another folder; Cancel: stop.
    static DialogResult CheckVersion(string ut)
    {
        string sys = Path.Combine(ut, "System");
        FileInfo newest = null;
        try
        {
            foreach (FileInfo f in new DirectoryInfo(sys).GetFiles("*.log"))
                if (f.Name.ToLowerInvariant() != "ucc.log" && (newest == null || f.LastWriteTime > newest.LastWriteTime))
                    newest = f;
        }
        catch { }
        if (newest == null)
            return DialogResult.Yes;
        string version = null, revision = null;
        try
        {
            using (StreamReader r = new StreamReader(newest.FullName))
                for (int i = 0; i < 40 && !r.EndOfStream; i++)
                {
                    string line = r.ReadLine();
                    Match m = Regex.Match(line, @"Init: Version: (\d+)");
                    if (m.Success) version = m.Groups[1].Value;
                    m = Regex.Match(line, @"Init: Revision: (\w)");
                    if (m.Success) revision = m.Groups[1].Value.ToLowerInvariant();
                }
        }
        catch { }
        if (version == null)
            return DialogResult.Yes;
        bool ok = string.CompareOrdinal(version, "469") >= 0;
        if (ok || Quiet)
            return DialogResult.Yes;
        string found = version + (revision ?? "");
        return MessageBox.Show(
            "The Aim Trainer is tested on Unreal Tournament 469f (players report 469b works too).\n" +
            "The game in\n\n" + ut + "\n\nsays it is " + found + ", which is older and untested: it may not load.\n" +
            "OldUnreal's 469 patches are at oldunreal.com.\n\n" +
            "Yes: install there anyway.\nNo: choose another Unreal Tournament folder.",
            Title, MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);
    }

    // ---------------------------------------------------------------- install

    static byte[] Resource(string name)
    {
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("AT." + name))
        {
            if (s == null)
                throw new Exception("Missing " + name + " inside the exe.");
            byte[] b = new byte[s.Length];
            int read = 0;
            while (read < b.Length)
                read += s.Read(b, read, b.Length - read);
            return b;
        }
    }

    static bool SameBytes(string path, byte[] data)
    {
        try
        {
            FileInfo fi = new FileInfo(path);
            if (!fi.Exists || fi.Length != data.Length)
                return false;
            byte[] old = File.ReadAllBytes(path);
            for (int i = 0; i < old.Length; i++)
                if (old[i] != data[i])
                    return false;
            return true;
        }
        catch { return false; }
    }

    static int Install(string ut)
    {
        int changed = 0;
        for (int i = 0; i < Files.GetLength(0); i++)
        {
            string dir = Path.Combine(ut, Files[i, 1]);
            string dest = Path.Combine(dir, Files[i, 0]);
            byte[] data = Resource(Files[i, 0]);
            if (SameBytes(dest, data))
                continue;
            Directory.CreateDirectory(dir);
            try
            {
                File.WriteAllBytes(dest, data);
            }
            catch (IOException)
            {
                throw new Exception("Can't write " + dest + ".\nIs Unreal Tournament running? Close it and try again.");
            }
            changed++;
        }
        return changed;
    }

    static void Uninstall(string ut)
    {
        if (!Quiet && MessageBox.Show("Remove the Aim Trainer from\n" + ut + "?\n\n(Your Aim Trainer settings and highscores in System\\AimTrainer.ini are kept.)",
                Title, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
            return;
        int removed = 0;
        for (int i = 0; i < Files.GetLength(0); i++)
        {
            string f = Path.Combine(Path.Combine(ut, Files[i, 1]), Files[i, 0]);
            if (File.Exists(f))
            {
                File.Delete(f);
                removed++;
            }
        }
        if (!Quiet)
            MessageBox.Show(removed + " file(s) removed.", Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    static void Launch(string ut)
    {
        string sys = Path.Combine(ut, "System");
        ProcessStartInfo p = new ProcessStartInfo(Path.Combine(sys, "UnrealTournament.exe"), StartUrl);
        p.WorkingDirectory = sys;
        p.UseShellExecute = false;
        Process.Start(p);
    }
}

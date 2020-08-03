using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.RegularExpressions;
#if UBOAT_ASSEMBLIES_IMPORTED
using DWS.Common.Editor;
using DWS.Common.Resources;
using UBOAT.Game.Core.Mods;
using UnityEditorInternal;
#endif
using UnityEditor;
using UnityEngine;
using Object = System.Object;

namespace UBOAT.Editor.ModdingTools
{
	public class ModdingTools
	{
		private static readonly string[] gameAssemblies = { "Editor Assemblies/com.dws.common.Editor.dll", "Editor Assemblies/com.uboat.editor.dll", "Editor Assemblies/com.unity.navmeshcomponents.Editor.dll", "com.dws.pipeline.Runtime.dll", "com.playway.water.Runtime.dll", "com.steamworks.net.dll", "com.uboat.dependencies.dll", "com.uboat.game.dll", "com.uboat.modapi.dll", "com.uboat.rendering.dll", "com.unity.postprocessing.Runtime.dll", "com.unity.postprocessingv1.Runtime.dll", "com.unity.standardassets.Runtime.dll", "EGIS.ShapeFileLib.dll", "FastExcel.dll", "System.Drawing.dll", "RoslynCSharp.dll", "UBOAT.App.Console.dll", "0Harmony.dll", "TeximpNet.dll" };
		private static readonly string[] editorAssemblies = { };

		[InitializeOnLoadMethod]
		public static void InitializeEditor()
		{
			EditorApplication.playModeStateChanged -= EditorApplicationOnPlayModeStateChanged;
			EditorApplication.playModeStateChanged += EditorApplicationOnPlayModeStateChanged;

			if (EditorPrefs.GetBool("UBOAT Wait for Compilation Finish", false))
			{
				EditorApplication.update -= DelayedDeployModsAndLaunch;
				EditorApplication.update += DelayedDeployModsAndLaunch;
			}

			string defines = PlayerSettings.GetScriptingDefineSymbolsForGroup(BuildTargetGroup.Standalone);

			if (!defines.Contains("UBOAT_ASSEMBLIES_IMPORTED"))
			{
				EditorApplication.update -= OpenModdingWelcomeWindow;
				EditorApplication.update += OpenModdingWelcomeWindow;
			}
			else
				CopyGameAssemblies();
		}

		private static void OpenModdingWelcomeWindow()
		{
			EditorApplication.update -= OpenModdingWelcomeWindow;

			ModdingWelcomeWindow.Open();
		}

		private static void EditorApplicationOnPlayModeStateChanged(PlayModeStateChange stateChange)
		{
			if (EditorApplication.isPlayingOrWillChangePlaymode)
			{
				EditorApplication.isPlaying = false;

				EditorApplication.update -= DelayedDeployModsAndLaunch;
				EditorApplication.update += DelayedDeployModsAndLaunch;
			}
		}

		private static void DelayedDeployModsAndLaunch()
		{
			if (EditorApplication.isCompiling)
			{
				EditorPrefs.SetBool("UBOAT Wait for Compilation Finish", true);
				EditorUtility.DisplayProgressBar("Please wait", "Waiting for compilation to finish...", 0.0f);
				return;
			}

			EditorPrefs.DeleteKey("UBOAT Wait for Compilation Finish");

			EditorApplication.update -= DelayedDeployModsAndLaunch;
			EditorUtility.ClearProgressBar();

#if UBOAT_ASSEMBLIES_IMPORTED
			DeployModsAndLaunch();
#endif
		}

		[MenuItem("Tools/Update Game Assemblies")]
		public static void CopyGameAssemblies()
		{
			string path = EditorPrefs.GetString("UBOAT Executable Path", "");

			if (string.IsNullOrWhiteSpace(path))
				return;

			path = Directory.GetParent(path).FullName;

			const string sourcePath = "UBOAT_Data/Managed/";
			const string targetPath = "Packages/com.uboat.assemblies/";
			const string backupsPath = "Packages/com.uboat.assemblies/Backup/";

			if (!Directory.Exists(targetPath))
				Directory.CreateDirectory(targetPath);

			string fullSourcePath = Path.Combine(path, sourcePath);
			string errorString = null;
			bool first = true;

			foreach (string assemblyName in gameAssemblies)
			{
				FileCopyIfExists(fullSourcePath, targetPath, assemblyName, ref errorString);
				FileCopyIfExists(backupsPath, targetPath, Path.GetFileName(assemblyName) + ".metax", Path.GetFileName(assemblyName) + ".meta", ref errorString);

				if (first)
				{
					first = false;

					if (errorString == null)
					{
						if (ModdingWelcomeWindow.Instance)
							ModdingWelcomeWindow.Instance.Close();
					}
					else
					{
						UnityEngine.Debug.LogError(errorString);
						return;
					}
				}
			}

			if (errorString == null)
			{
				foreach (string editorAssemblyName in editorAssemblies)
					FileCopyIfExists(backupsPath, targetPath, editorAssemblyName + "x", editorAssemblyName, ref errorString);
			}

			if (errorString == null)
			{
				EditorPrefs.SetBool("UBOAT Assemblies Imported", true);

				string defines = PlayerSettings.GetScriptingDefineSymbolsForGroup(BuildTargetGroup.Standalone);

				if (!defines.Contains("UBOAT_ASSEMBLIES_IMPORTED"))
					PlayerSettings.SetScriptingDefineSymbolsForGroup(BuildTargetGroup.Standalone, (string.IsNullOrWhiteSpace(defines) ? "" : (defines + " ")) + "UBOAT_ASSEMBLIES_IMPORTED");

				AssetDatabase.Refresh();

				// Unity usually presents some one-time errors at this point, probably caused by copying all DLLs at once; they seem to be harmless
				ClearConsole();
			}
			else
			{
				UnityEngine.Debug.LogError(errorString);

				AssetDatabase.Refresh();
			}
		}

		private static void ClearConsole()
		{
			var assembly = Assembly.GetAssembly(typeof(SceneView));
			var type = assembly.GetType("UnityEditor.LogEntries");

			if (type == null)
				return;

			var method = type.GetMethod("Clear");
			method?.Invoke(new object(), null);
		}

		private static bool FileCopyIfExists(string path, string target, string fileName, ref string error)
		{
			path = Path.Combine(path, fileName);

			if (File.Exists(path))
			{
				try
				{
					File.Copy(path, Path.Combine(target, Path.GetFileName(fileName)), true);
				}
				catch (Exception e)
				{
					if (error == null)
					{
						if (IsDiskFull(e))
							error = "Ran out of disk space while copying game DLL assemblies.";
						else
							error = e.ToString();
					}
				}

				return true;
			}
			else if(error == null)
			{
				error = $"Couldn't locate required assembly \"{fileName}\" in the selected game directory. Are you sure, that this is the correct location?";
			}

			return false;
		}

		private static bool FileCopyIfExists(string path, string target, string fileNameSource, string fileNameTarget, ref string error)
		{
			path = Path.Combine(path, fileNameSource);

			if (File.Exists(path))
			{
				try
				{
					File.Copy(path, Path.Combine(target, fileNameTarget), true);
				}
				catch (Exception e)
				{
					if (error == null)
					{
						if (IsDiskFull(e))
							error = "Ran out of disk space while copying game DLL assemblies.";
						else
							error = e.ToString();
					}
				}

				return true;
			}
			else if (error == null)
			{
				error = $"Couldn't locate required assembly \"{fileNameTarget}\" in the selected game directory. Are you sure, that this is the correct location?";
			}

			return false;
		}

		[PreferenceItem("UBOAT Modding")]
		public static void ModdingToolsSettings()
		{
			string path = EditorPrefs.GetString("UBOAT Executable Path", "");

			GUILayout.BeginHorizontal();
			EditorGUILayout.LabelField("Game executable path", GUILayout.Width(150));
			path = GUILayout.TextField(path, GUILayout.Width(180));

			if (GUILayout.Button("...", GUILayout.Width(40)))
			{
				string path1 = EditorUtility.OpenFilePanel("Open...", "", "exe");

				if(!string.IsNullOrWhiteSpace(path1))
					path = path1;
			}

			GUILayout.EndHorizontal();

			GUILayout.BeginHorizontal();
			var gameLaunchMode = (GameLaunchMode)EditorPrefs.GetInt("UBOAT Executable Launch Mode", 1);
			EditorGUILayout.LabelField("Launch mode", GUILayout.Width(150));
			gameLaunchMode = (GameLaunchMode)EditorGUILayout.EnumPopup(gameLaunchMode, GUILayout.Width(180));

			GUILayout.EndHorizontal();

			if (GUI.changed)
			{
				string previousExecutablePath = EditorPrefs.GetString("UBOAT Executable Path", "");

				if (previousExecutablePath != path)
				{
					EditorPrefs.SetString("UBOAT Executable Path", path);
					CopyGameAssemblies();
				}

				EditorPrefs.SetInt("UBOAT Executable Launch Mode", (int)gameLaunchMode);
			}
		}

#if UBOAT_ASSEMBLIES_IMPORTED
		[MenuItem("Tools/Remove Game Assemblies")]
		private static void RemoveGameAssemblies()
		{
			const string targetPath = "Packages/com.uboat.assemblies/";
			const string backupsPath = "Packages/com.uboat.assemblies/Backup/";

			foreach (string assemblyName1 in gameAssemblies)
			{
				string assemblyName = Path.GetFileName(assemblyName1);

				if (File.Exists(targetPath + assemblyName + ".meta"))
				{
					File.Copy(targetPath + assemblyName + ".meta", backupsPath + assemblyName + ".metax", true);
					File.Delete(targetPath + assemblyName + ".meta");
				}

				if (File.Exists(targetPath + assemblyName))
					File.Delete(targetPath + assemblyName);
			}

			foreach (string editorAssemblyName in editorAssemblies)
			{
				if (File.Exists(targetPath + editorAssemblyName + ".meta"))
				{
					File.Copy(targetPath + editorAssemblyName + ".meta", backupsPath + editorAssemblyName + ".metax", true);
					File.Delete(targetPath + editorAssemblyName + ".meta");
				}

				if (File.Exists(targetPath + editorAssemblyName))
				{
					File.Copy(targetPath + editorAssemblyName, backupsPath + editorAssemblyName + "x", true);
					File.Delete(targetPath + editorAssemblyName);
				}
			}

			string defines = PlayerSettings.GetScriptingDefineSymbolsForGroup(BuildTargetGroup.Standalone);

			if (defines.Contains("UBOAT_ASSEMBLIES_IMPORTED"))
				PlayerSettings.SetScriptingDefineSymbolsForGroup(BuildTargetGroup.Standalone, defines.Replace("UBOAT_ASSEMBLIES_IMPORTED", "").Trim());

			AssetDatabase.Refresh();
		}

		//[MenuItem("Tools/Build Asset Bundles")]
		private static void BuildAssetBundles()
		{
			EditorUtility.DisplayProgressBar("Building asset bundles", "Please wait...", 0.0f);

			var descriptors = AssetDatabase.FindAssets("t:AssetBundleDescriptor");

			for (int i = 0; i < descriptors.Length; ++i)
			{
				string path = AssetDatabase.GUIDToAssetPath(descriptors[i]);
				var descriptor = AssetDatabase.LoadAssetAtPath<AssetBundleDescriptor>(path);
				AssetBundleDescriptorEditorUtilities.RebuildPaths(descriptor);
			}

			AssetDatabase.SaveAssets();

			const string assetBundleDirectory = "Temp/Bundles";

			if (!Directory.Exists(assetBundleDirectory))
				Directory.CreateDirectory(assetBundleDirectory);

			var assetBundleNames = AssetDatabase.GetAllAssetBundleNames();
			var assetBundleBuilds = new List<AssetBundleBuild>();

			foreach (string assetBundleName in assetBundleNames)
			{
				var buildInfo = DeepBuildPipeline.GetAssetBundleBuildInfo(assetBundleName);
				assetBundleBuilds.Add(buildInfo);
			}

			BuildPipeline.BuildAssetBundles(assetBundleDirectory, assetBundleBuilds.ToArray(), BuildAssetBundleOptions.UncompressedAssetBundle | BuildAssetBundleOptions.DisableLoadAssetByFileNameWithExtension, BuildTarget.StandaloneWindows);

			var files = Directory.GetFiles(assetBundleDirectory);

			for (int i = 0; i < files.Length; ++i)
			{
				string filePath = files[i];
				string fileName = Path.GetFileName(filePath);
				string modName = fileName.Replace(".manifest", "");

				int dotIndex = modName.LastIndexOf('.');

				if (dotIndex != -1)
					modName = modName.Substring(0, dotIndex);

				//string modName = file.Contains(".") ? file.Substring(0, file.IndexOf('.')) : file;

				if (modName == "Bundles")
				{
					File.Delete(filePath);
					continue;
				}

				string modDir = $"Assets/Mods/{modName}/";

				if (!Directory.Exists(modDir))
					Directory.CreateDirectory(modDir);

				string targetDir = modDir + "Bundles/";

				if (!Directory.Exists(targetDir))
					Directory.CreateDirectory(targetDir);

				string targetPath = targetDir + fileName;

				if (File.Exists(targetPath))
					File.Delete(targetPath);

				File.Move(filePath, targetPath);
			}

			EditorUtility.ClearProgressBar();
		}

		[MenuItem("Tools/Deploy Mods")]
		public static void DeployMods()
		{
			var copiedAssemblies = new List<string>();
			DeployAssemblies(copiedAssemblies);
			BuildAssetBundles();
			DeployModFiles(copiedAssemblies);
		}

		private static void DeployModFiles(List<string> copiedAssemblies)
		{
			const string modsDir = "Assets/Mods/";
			string targetModsDir = Path.GetDirectoryName(Application.persistentDataPath) + "/UBOAT/Mods/";
			var mods = Directory.GetDirectories(modsDir);

			for (int i = 0; i < mods.Length; ++i)
			{
				string projectModDir = mods[i];
				string modName = Path.GetFileName(projectModDir);

				if (modName != null && modName != "uboat")
				{
					string targetModDir = targetModsDir + modName;

					UpdateProjectJson(projectModDir, targetModDir);

					if (Directory.Exists(targetModDir))
						DeleteDirectoryContentsExceptCopiedAssemblies(targetModDir, copiedAssemblies);

					CopyAll(projectModDir, targetModDir);
				}
			}
		}

		private static void UpdateProjectJson(string projectModDir, string targetModDir)
		{
			string targetJsonPath = Path.Combine(targetModDir, "Manifest.json");
			string projectJsonPath = Path.Combine(projectModDir, "Manifest.json");

			if (File.Exists(targetJsonPath) && File.Exists(projectJsonPath))
			{
				string targetJson = File.ReadAllText(targetJsonPath);
				var targetManifest = JsonUtility.FromJson<ModManager.ModManifest>(targetJson);

				if (targetManifest.steamFileId != 0)
				{
					string projectJson = File.ReadAllText(projectJsonPath);
					var projectManifest = JsonUtility.FromJson<ModManager.ModManifest>(projectJson);

					var asmDefFiles = Directory.GetFiles(projectModDir, "*.asmdef");
					var assemblyDefinitionAsset = asmDefFiles.Length != 0 ? AssetDatabase.LoadAssetAtPath(asmDefFiles[0], typeof(AssemblyDefinitionAsset)) : null;
					string assemblyName = assemblyDefinitionAsset ? assemblyDefinitionAsset.name : null;

					if (targetManifest.steamFileId != projectManifest.steamFileId || (projectManifest.assemblyName != assemblyName))
					{
						projectManifest.steamFileId = targetManifest.steamFileId;
						projectManifest.assemblyName = assemblyName;

						projectJson = JsonUtility.ToJson(projectManifest, true);
						File.WriteAllText(projectJsonPath, projectJson);
					}
				}
			}
		}

		private static void DeleteDirectoryContentsExceptCopiedAssemblies(string targetDirectory, List<string> copiedAssemblies)
		{
			foreach (var file in Directory.GetFiles(targetDirectory))
			{
				if(!copiedAssemblies.Contains(Path.GetFullPath(file)))
					File.Delete(file);
			}

			foreach (var dir in Directory.GetDirectories(targetDirectory))
				Directory.Delete(dir, true);
		}

		private static void DeployAssemblies(List<string> copiedAssemblies)
		{
			const string modsDir = "Assets/Mods/";
			string targetAssembliesDir = Path.GetDirectoryName(Application.persistentDataPath) + "/UBOAT/Temp/";
			var mods = Directory.GetDirectories(modsDir);

			for (int i = 0; i < mods.Length; ++i)
			{
				string projectModDir = mods[i];
				string modName = Path.GetFileName(projectModDir);

				if (modName != null && modName != "uboat")
				{
					if (Directory.GetFiles(projectModDir, "*.cs", SearchOption.AllDirectories).Length != 0)
					{
						string alphanumericModName = Regex.Replace(modName, "[^A-Za-z0-9 _\\-]", "");
						string compiledDllPath = "Library/ScriptAssemblies/" + alphanumericModName + ".dll";
						string compiledMdbPath = "Library/ScriptAssemblies/" + alphanumericModName + ".dll.mdb";

						if (File.Exists(compiledDllPath))
						{
							string targetDllPath = targetAssembliesDir + alphanumericModName + ".dll";
							copiedAssemblies.Add(Path.GetFullPath(targetDllPath));
							File.Copy(compiledDllPath, targetDllPath, true);

							if (File.Exists(compiledMdbPath))
							{
								string targetMdbPath = targetAssembliesDir + alphanumericModName + ".dll.mdb";
								copiedAssemblies.Add(Path.GetFullPath(targetMdbPath));
								File.Copy(compiledMdbPath, targetMdbPath, true);
							}
							else
								UnityEngine.Debug.LogError($"Couldn't locate mod \"{modName}\" assembly debugging symbols file (.mdb). Debugging will be impossible.");
						}
						else
							UnityEngine.Debug.LogError($"Couldn't locate mod \"{modName}\" assembly file (.dll). Debugging will be impossible.");
					}
				}
			}
		}

		[MenuItem("Tools/Deploy Mods and Launch")]
		public static void DeployModsAndLaunch()
		{
			string path = EditorPrefs.GetString("UBOAT Executable Path", "");

			if (string.IsNullOrWhiteSpace(path))
			{
				EditorUtility.DisplayDialog("Warning", "UBOAT executable path is not set. Please enter \"Edit/Preferences\" menu and choose executable path in \"UBOAT Modding\" section.", "Ok");
				return;
			}

			DeployMods();

			var gameLaunchMode = (GameLaunchMode)EditorPrefs.GetInt("UBOAT Executable Launch Mode", 1);

			switch (gameLaunchMode)
			{
				case GameLaunchMode.Normal:
				{
					if (path.Contains("steamapps"))
						Process.Start("steam://run/494840");
					else
						Process.Start(path);

					break;
				}

				case GameLaunchMode.WaitForDebugger:
				{
					if (path.Contains("steamapps"))
						Process.Start("steam://run/494840/?launchMode=waitForDebugger");
					else
						Process.Start(path, "waitForDebugger");

					break;
				}

				case GameLaunchMode.QuickLaRochelle:
				{
					if (path.Contains("steamapps"))
						Process.Start("steam://run/494840/?launchMode=quickLaRochelle");
					else
						Process.Start(path, "quickLaRochelle");

					break;
				}

				case GameLaunchMode.QuickAtlantic:
				{
					if (path.Contains("steamapps"))
						Process.Start("steam://run/494840/?launchMode=quickAtlantic");
					else
						Process.Start(path, "quickAtlantic");

					break;
				}

				case GameLaunchMode.QuickLatestGameState:
				{
					if (path.Contains("steamapps"))
						Process.Start("steam://run/494840/?launchMode=quickLatestGameState");
					else
						Process.Start(path, "quickLatestGameState");

					break;
				}
			}
		}
#endif

		private static void CopyAll(string sourceDirectory, string targetDirectory)
		{
			DirectoryInfo diSource = new DirectoryInfo(sourceDirectory);
			DirectoryInfo diTarget = new DirectoryInfo(targetDirectory);

			CopyAll(diSource, diTarget);
		}

		private static void CopyAll(DirectoryInfo source, DirectoryInfo target)
		{
			Directory.CreateDirectory(target.FullName);

			foreach (FileInfo fi in source.GetFiles())
			{
				if(fi.Extension != ".meta" && fi.Extension != ".asmdef")
					fi.CopyTo(Path.Combine(target.FullName, fi.Name), true);
			}

			foreach (DirectoryInfo diSourceSubDir in source.GetDirectories())
			{
				DirectoryInfo nextTargetSubDir = target.CreateSubdirectory(diSourceSubDir.Name);
				CopyAll(diSourceSubDir, nextTargetSubDir);
			}
		}

		private static bool IsDiskFull(Exception e)
		{
			const int HR_ERROR_HANDLE_DISK_FULL = unchecked((int)0x80070027);
			const int HR_ERROR_DISK_FULL = unchecked((int)0x80070070);

			return e is IOException && (e.HResult == HR_ERROR_HANDLE_DISK_FULL || e.HResult == HR_ERROR_DISK_FULL);
		}

		private enum GameLaunchMode
		{
			Normal,
			WaitForDebugger,
			QuickLaRochelle,
			QuickAtlantic,
			QuickLatestGameState
		}
	}
}

using System.IO;

namespace PlayWay.Water
{
	/// <summary>
	/// Helps locating the PlayWay Water folder and find stuff in it.
	/// </summary>
	public static class WaterPackageUtilities
	{
#if UNITY_EDITOR
		private static readonly string waterSpecificPath = "PlayWay Water" + Path.DirectorySeparatorChar + "Textures";
		private static string waterPackagePath;
		
		public static string WaterPackagePath
		{
			get
			{
				return waterPackagePath ?? (waterPackagePath = Find("Assets" + Path.DirectorySeparatorChar, "")) ?? (waterPackagePath = Find("Packages" + Path.DirectorySeparatorChar, ""));
			}
		}

		[UnityEditor.ShaderIncludePath]
		public static string[] GetPaths()
		{
			string waterPackagePath = WaterPackagePath;
			return waterPackagePath != null ? new[]
			{
				Directory.GetParent(waterPackagePath).ToString()
			} : new string[0];
		}
		
		public static T FindDefaultAsset<T>(string searchString, string searchStringFallback) where T : UnityEngine.Object
		{
			var guids = UnityEditor.AssetDatabase.FindAssets(searchString);

			if(guids.Length == 0)
				guids = UnityEditor.AssetDatabase.FindAssets(searchStringFallback);

			if(guids.Length == 0)
				return null;

			UnityEditorInternal.InternalEditorUtility.RepaintAllViews();
			string path = UnityEditor.AssetDatabase.GUIDToAssetPath(guids[0]);
			return UnityEditor.AssetDatabase.LoadAssetAtPath<T>(path);
		}

		private static string Find(string directory, string parentDirectory)
		{
			if(directory.EndsWith(waterSpecificPath))
				return parentDirectory.Replace(Path.DirectorySeparatorChar, '/');

			foreach(string subDirectory in Directory.GetDirectories(directory))
			{
				string result = Find(subDirectory, directory);

				if(result != null)
					return result;
			}

			return null;
		}
#endif
	}
}
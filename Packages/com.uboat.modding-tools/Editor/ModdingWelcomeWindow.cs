using System.Diagnostics;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace UBOAT.Editor.ModdingTools
{
	public class ModdingWelcomeWindow : EditorWindow
	{
		private GUIStyle layoutStyle;
		private GUIStyle labelStyle;
		private GUIStyle hyperlinkStyle;
		private GUIStyle hyperlinkUnderline;
		private Texture2D fillTex;
		private Texture2D welcomeTex;

		private static readonly Color32 hyperlinkColor = new Color32(86, 156, 214, 255);
		private static readonly Color32 hyperlinkHoverColor = new Color32(94, 166, 234, 255);

		public static ModdingWelcomeWindow Instance;

		[MenuItem("Window/Modding Welcome")]
		public static void Open()
		{
			if (Instance)
				return;

			Instance = CreateInstance<ModdingWelcomeWindow>();
			Instance.titleContent = new GUIContent("Welcome!");
			Instance.Show();
		}

		public void OnEnable()
		{
			if (fillTex)
				DestroyImmediate(fillTex);

			fillTex = new Texture2D(2, 2, TextureFormat.ARGB32, false);
			fillTex.SetPixel(0, 0, hyperlinkColor);
			fillTex.SetPixel(0, 1, hyperlinkColor);
			fillTex.SetPixel(1, 0, hyperlinkColor);
			fillTex.SetPixel(1, 1, hyperlinkColor);
			fillTex.Apply();

			if(!welcomeTex)
				welcomeTex = AssetDatabase.LoadAssetAtPath<Texture2D>("Packages/com.uboat.modding-tools/Editor/Welcome Image.png");

			layoutStyle = new GUIStyle();
			layoutStyle.margin = new RectOffset(30, 30, 30, 30);

			hyperlinkUnderline = new GUIStyle();
			hyperlinkUnderline.margin = new RectOffset();
			hyperlinkUnderline.padding = new RectOffset();
			hyperlinkUnderline.normal.background = fillTex;

			labelStyle = null;
			hyperlinkStyle = null;

			var position = new Rect(0, 0, 800, 800);
			position.center = new Rect(0.0f, 0.0f, Screen.width, Screen.height).center;
			this.position = position;
		}

		public void OnGUI()
		{
			if (labelStyle == null)
			{
				labelStyle = new GUIStyle(EditorStyles.label);
				labelStyle.wordWrap = true;
				labelStyle.fontSize = 14;

				hyperlinkStyle = new GUIStyle(EditorStyles.label);
				hyperlinkStyle.normal.textColor = hyperlinkColor;
				hyperlinkStyle.hover.textColor = hyperlinkHoverColor;
				hyperlinkStyle.wordWrap = false;
				hyperlinkStyle.fontSize = 14;
			}

			if (!Directory.Exists("Assets/Mods"))
				return;

			string userModPath = GetFirstUserMod();

			EditorGUILayout.BeginVertical(layoutStyle, GUILayout.MaxWidth(800));

			EditorGUILayout.BeginHorizontal();
			GUILayout.FlexibleSpace();
			GUILayout.Box(welcomeTex);
			GUILayout.FlexibleSpace();
			EditorGUILayout.EndHorizontal();

			GUILayout.Label("\nWelcome!\n\nThank you for your interest in modding UBOAT.\n\nBefore you start, be sure to enter preferences (Edit menu > Preferences > UBOAT Modding tab) and set a path to your UBOAT installation folder.\n\nSingle project in Unity Editor can be used to develop multiple mods at a time. Launcher already created a suggested structure for your first mod inside this project:\n", labelStyle, GUILayout.MaxWidth(800));

			EditorGUILayout.BeginHorizontal();
			GUILayout.Label("• ", labelStyle);

			if (GUILayout.Button(userModPath, hyperlinkStyle))
			{
				Process.Start(Path.Combine(Directory.GetCurrentDirectory(), userModPath));
			}

			DrawHyperlinkUnderline();

			GUILayout.FlexibleSpace();
			EditorGUILayout.EndHorizontal();

			GUILayout.Label("This is a staging folder that contains exactly what your mod's subscribers will download. Place your C# scripts and config sheets into this folder. Such files don't need extra processing and should be supplied as-is with the mod.\n", labelStyle);

			EditorGUILayout.BeginHorizontal();
			GUILayout.Label("• ", labelStyle);

			if (GUILayout.Button(userModPath.Replace("/Mods/", "/Packages/"), hyperlinkStyle))
			{
				Process.Start(Path.Combine(Directory.GetCurrentDirectory(), userModPath.Replace("/Mods/", "/Packages/")));
			}

			DrawHyperlinkUnderline();

			GUILayout.FlexibleSpace();
			EditorGUILayout.EndHorizontal();

			GUILayout.Label("This folder contains assets that will be automatically packed into an Asset Bundle that will be supplied with your mod. You generally should place all textures, models and prefabs there.\n\nIf you would like to include Unity scenes in your mod, you can place them here too, but they need to be manually assigned to their own asset bundles (one bundle per scene with no assets).\n", labelStyle);

			GUILayout.Label("To deploy & test your mod in the game hit the play button at the top of the Unity Editor.\n\nTo learn how to actually create mods, please visit UBOAT wiki at fandom and/or check our samples. We hope that you will enjoy working on this game as much as we do.\n\nKind regards,\nDeep Water Studio", labelStyle);

			EditorGUILayout.EndVertical();
		}

		private void DrawHyperlinkUnderline()
		{
			var lastRect = GUILayoutUtility.GetLastRect();
			lastRect.y += lastRect.height - 1;
			lastRect.height = 1;
			GUI.Box(lastRect, "", hyperlinkUnderline);
		}

		private static string GetFirstUserMod()
		{
			var directories = Directory.GetDirectories("Assets/Mods");

			foreach (string directoryPath in directories)
			{
				string directoryName = Path.GetFileName(directoryPath);

				if (directoryName != "uboat" && !directoryName.StartsWith("uboat."))
					return "Assets/Mods/" + directoryName;
			}

			foreach (string directoryPath in directories)
			{
				string directoryName = Path.GetFileName(directoryPath);

				if (directoryName != "uboat")
					return "Assets/Mods/" + directoryName;
			}

			return "Assets/Mods/";
		}
	}
}

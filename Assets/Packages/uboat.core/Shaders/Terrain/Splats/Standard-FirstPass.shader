Shader "Nature/Terrain/Standard (DWS)" {
	Properties {
		// set by terrain engine
		[HideInInspector] _Control ("Control (RGBA)", 2D) = "red" {}
		_Splat4 ("Layer 4 (A)", 2D) = "white" {}
		[HideInInspector] _Splat3 ("Layer 3 (A)", 2D) = "white" {}
		[HideInInspector] _Splat2 ("Layer 2 (B)", 2D) = "white" {}
		[HideInInspector] _Splat1 ("Layer 1 (G)", 2D) = "white" {}
		[HideInInspector] _Splat0 ("Layer 0 (R)", 2D) = "white" {}
		_Normal4 ("Normal 4 (A)", 2D) = "bump" {}
		[HideInInspector] _Normal3 ("Normal 3 (A)", 2D) = "bump" {}
		[HideInInspector] _Normal2 ("Normal 2 (B)", 2D) = "bump" {}
		[HideInInspector] _Normal1 ("Normal 1 (G)", 2D) = "bump" {}
		[HideInInspector] _Normal0 ("Normal 0 (R)", 2D) = "bump" {}
		[HideInInspector] [Gamma] _Metallic0 ("Metallic 0", Range(0.0, 1.0)) = 0.0	
		[HideInInspector] [Gamma] _Metallic1 ("Metallic 1", Range(0.0, 1.0)) = 0.0	
		[HideInInspector] [Gamma] _Metallic2 ("Metallic 2", Range(0.0, 1.0)) = 0.0	
		[HideInInspector] [Gamma] _Metallic3 ("Metallic 3", Range(0.0, 1.0)) = 0.0
		[Gamma] _Metallic4 ("Metallic 4", Range(0.0, 1.0)) = 0.0
		[HideInInspector] _Smoothness0 ("Smoothness 0", Range(0.0, 1.0)) = 1.0	
		[HideInInspector] _Smoothness1 ("Smoothness 1", Range(0.0, 1.0)) = 1.0	
		[HideInInspector] _Smoothness2 ("Smoothness 2", Range(0.0, 1.0)) = 1.0	
		[HideInInspector] _Smoothness3 ("Smoothness 3", Range(0.0, 1.0)) = 1.0
		_Smoothness4 ("Smoothness 4", Range(0.0, 1.0)) = 1.0

		_GlobalColor("Global Color", 2D) = "white" {}
		_AmbientOcclusion ("Ambient Occlusion", 2D) = "black" {}

		_Coordinates ("Coordinates", Vector) = (0, 0, 1, 1)

		// used in fallback on old cards & base map
		[HideInInspector] _MainTex ("BaseMap (RGB)", 2D) = "white" {}
		[HideInInspector] _Color ("Main Color", Color) = (1,1,1,1)
	}

	SubShader {
		Tags {
			"SplatCount" = "4"
			"Queue" = "Geometry-100"
			"RenderType" = "Opaque"
		}

		CGPROGRAM
		#pragma surface surf Standard vertex:SplatmapVert finalcolor:SplatmapFinalColor finalgbuffer:SplatmapFinalGBuffer fullforwardshadows
		#pragma multi_compile _ USE_CUSTOM_AMBIENT
		#define UNITY_HDR_ON 1
		#pragma target 4.0
		// needs more than 8 texcoords
		#pragma exclude_renderers gles
		#include "UnityPBSLighting.cginc"

		#pragma multi_compile __ _TERRAIN_NORMAL_MAP
		#if defined(SHADER_API_D3D9) && defined(SHADOWS_SCREEN) && defined(LIGHTMAP_ON) && defined(DIRLIGHTMAP_COMBINED) && defined(DYNAMICLIGHTMAP_ON) && defined(SHADOWS_SHADOWMASK) && defined(_TERRAIN_NORMAL_MAP) && defined(UNITY_SPECCUBE_BLENDING)
			// TODO : On d3d9 17 samplers would be used when : defined(SHADOWS_SCREEN) && defined(LIGHTMAP_ON) && defined(DIRLIGHTMAP_COMBINED) && defined(DYNAMICLIGHTMAP_ON) && defined(SHADOWS_SHADOWMASK) && defined(_TERRAIN_NORMAL_MAP) && defined(UNITY_SPECCUBE_BLENDING)
			// In that case it would be probably acceptable to undef UNITY_SPECCUBE_BLENDING however at the moment (10/2/2016) we can't undef UNITY_SPECCUBE_BLENDING or other platform defines. CGINCLUDE being added after "Lighting.cginc".
			// For now, remove _TERRAIN_NORMAL_MAP in that case.
			#undef _TERRAIN_NORMAL_MAP
		#endif

		#define TERRAIN_STANDARD_SHADER
		#define TERRAIN_SURFACE_OUTPUT SurfaceOutputStandard
		#include "TerrainSplatmapCommon.cginc"

		half _Metallic0;
		half _Metallic1;
		half _Metallic2;
		half _Metallic3;
		half _Metallic4;
		
		half _Smoothness0;
		half _Smoothness1;
		half _Smoothness2;
		half _Smoothness3;
		half _Smoothness4;

		float3 _Coordinates;
		sampler2D _AmbientOcclusion;
		sampler2D _GlobalColor;

		void surf (Input IN, inout SurfaceOutputStandard o) {
			half4 splat_control;
			half weight;
			fixed4 mixedDiffuse;
			half4 defaultSmoothness = half4(_Smoothness0, _Smoothness1, _Smoothness2, _Smoothness3);
			SplatmapMix(IN, defaultSmoothness, splat_control, weight, mixedDiffuse, o.Normal);
			o.Albedo = mixedDiffuse.rgb;
			o.Albedo = lerp(o.Albedo, tex2D(_GlobalColor, _Coordinates.xy + IN.tc_Control.xy * _Coordinates.zz * float2(1.0, 2.0)), _GlobalMapAlbedoMix);
			o.Alpha = 1.0;
			o.Occlusion = 1.0 - tex2D(_AmbientOcclusion, IN.tc_Control);

			half fifthTexIntensity = 1.0 - weight;
			o.Smoothness = mixedDiffuse.a;
			o.Metallic = dot(splat_control, half4(_Metallic0, _Metallic1, _Metallic2, _Metallic3)) + _Metallic4 * fifthTexIntensity;
		}
		ENDCG
	}

	Dependency "AddPassShader" = "Hidden/TerrainEngine/Splatmap/Standard-AddPass"
	Dependency "BaseMapShader" = "Hidden/TerrainEngine/Splatmap/Standard-Base"

	Fallback "Nature/Terrain/Diffuse"
}

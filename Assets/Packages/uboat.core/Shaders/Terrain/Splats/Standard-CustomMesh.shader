Shader "Nature/Terrain/Standard (DWS) - Custom Mesh" {
	Properties {
		_ColorMultiplier ("Color", Color) = (1.0, 1.0, 1.0, 1.0)
		_Control ("Control (RGBA)", 2D) = "red" {}
		_Splat3 ("Layer 3 (A)", 2D) = "white" {}
		_Splat2 ("Layer 2 (B)", 2D) = "white" {}
		_Splat1 ("Layer 1 (G)", 2D) = "white" {}
		_Splat0 ("Layer 0 (R)", 2D) = "white" {}
		_Normal3 ("Normal 3 (A)", 2D) = "bump" {}
		_Normal2 ("Normal 2 (B)", 2D) = "bump" {}
		_Normal1 ("Normal 1 (G)", 2D) = "bump" {}
		_Normal0 ("Normal 0 (R)", 2D) = "bump" {}
		_ParallaxMap3 ("Height Map 3 (A)", 2D) = "gray" {}
		_Parallax ("Parallax", Float) = 0.04
		[Gamma] _Metallic0 ("Metallic 0", Range(0.0, 1.0)) = 0.0	
		[Gamma] _Metallic1 ("Metallic 1", Range(0.0, 1.0)) = 0.0	
		[Gamma] _Metallic2 ("Metallic 2", Range(0.0, 1.0)) = 0.0	
		[Gamma] _Metallic3 ("Metallic 3", Range(0.0, 1.0)) = 0.0
		_Smoothness0 ("Smoothness 0", Range(0.0, 1.0)) = 1.0	
		_Smoothness1 ("Smoothness 1", Range(0.0, 1.0)) = 1.0	
		_Smoothness2 ("Smoothness 2", Range(0.0, 1.0)) = 1.0	
		_Smoothness3 ("Smoothness 3", Range(0.0, 1.0)) = 1.0

		_NormalMapsIntensity ("Normals Intensity", Float) = 1.0

		_NoiseFrequency ("Noise Frequency", Float) = 0.1
		_NoiseIntensity ("Noise Intensity", Range(0.0, 1.0)) = 0.2
		_NoiseDistanceFactor ("Noise Distance Factor", Float) = 0.01

		_MainTex ("Base Albedo", 2D) = "grey" {}
		_MetallicGlossMap ("Metallic", 2D) = "white" {}

		_Coordinates ("Coordinates", Vector) = (0, 0, 1, 1)

		// used in fallback on old cards & base map
		[HideInInspector] _Color ("Main Color", Color) = (1,1,1,1)
	}

	SubShader {
		Tags {
			"SplatCount" = "4"
			"Queue" = "Geometry-100"
			"RenderType" = "Opaque"
		}

		Pass
		{
			Name "Motion Vectors"
			Tags{ "LightMode" = "MotionVectors" }

			ZTest LEqual
			Cull Back
			ZWrite Off

			CGPROGRAM
			#pragma multi_compile _ _DISSOLVE
			//#pragma multi_compile _ _DEEP_PIPELINE

			#define _DEEP_PIPELINE 1
			#define UNITY_HDR_ON 1

			#pragma vertex VertMotionVectors
			#pragma fragment FragMotionVectors

			#include "../../DeepStandard/UnityStandardCore.cginc"
			ENDCG
		}

		CGPROGRAM
		#pragma surface surf Standard vertex:SplatmapVert finalcolor:SplatmapFinalColor finalgbuffer:SplatmapFinalGBuffer fullforwardshadows
		#pragma multi_compile _ USE_CUSTOM_AMBIENT
		//#pragma multi_compile _ _DEEP_PIPELINE

		#pragma target 4.0
		// needs more than 8 texcoords
		#pragma exclude_renderers gles
		#define UNITY_HDR_ON 1
		//#include "../../DeepStandard/UnityStandardCore.cginc"
		#include "UnityPBSLighting.cginc"
		#include "Assets/PlayWay Water/Shaders/Utility/NoiseLib.cginc"

		#define COMPENSATE_EARTH_CURVATURE_PER_VERTEX 1
		#include "PlayWay Water/Shaders/Includes/EarthCurvature.cginc"

		#pragma multi_compile __ _TERRAIN_NORMAL_MAP
		#if defined(SHADER_API_D3D9) && defined(SHADOWS_SCREEN) && defined(LIGHTMAP_ON) && defined(DIRLIGHTMAP_COMBINED) && defined(DYNAMICLIGHTMAP_ON) && defined(SHADOWS_SHADOWMASK) && defined(_TERRAIN_NORMAL_MAP) && defined(UNITY_SPECCUBE_BLENDING)
			// TODO : On d3d9 17 samplers would be used when : defined(SHADOWS_SCREEN) && defined(LIGHTMAP_ON) && defined(DIRLIGHTMAP_COMBINED) && defined(DYNAMICLIGHTMAP_ON) && defined(SHADOWS_SHADOWMASK) && defined(_TERRAIN_NORMAL_MAP) && defined(UNITY_SPECCUBE_BLENDING)
			// In that case it would be probably acceptable to undef UNITY_SPECCUBE_BLENDING however at the moment (10/2/2016) we can't undef UNITY_SPECCUBE_BLENDING or other platform defines. CGINCLUDE being added after "Lighting.cginc".
			// For now, remove _TERRAIN_NORMAL_MAP in that case.
			#undef _TERRAIN_NORMAL_MAP
		#endif

		#define TERRAIN_STANDARD_SHADER 1
		#define DONT_USE_ELEVATION_DATA 1
		#define TERRAIN_SURFACE_OUTPUT SurfaceOutputStandard
		//#include "TerrainSplatmapCommon.cginc"

		half _Metallic0;
		half _Metallic1;
		half _Metallic2;
		half _Metallic3;
		
		half _Smoothness0;
		half _Smoothness1;
		half _Smoothness2;
		half _Smoothness3;
		half4 _ColorMultiplier;
		half _NormalMapsIntensity;

		half _GlobalMapAlbedoMix;
		float3 _Coordinates;
		sampler2D _MetallicGlossMap;
		sampler2D _MainTex;

		struct Input
		{
			float2 uv2_Splat0 : TEXCOORD0;
			float2 uv2_Splat1 : TEXCOORD1;
			float2 uv2_Splat2 : TEXCOORD2;
			float2 uv2_Splat3 : TEXCOORD3;
			float2 tc_Control : TEXCOORD4;	// Not prefixing '_Contorl' with 'uv' allows a tighter packing of interpolators, which is necessary to support directional lightmap.
			float3 worldPos	: TEXCOORD5;
			float elevation : TEXCOORD6;
			float3 viewDir : TEXCOORD7;
		};

		sampler2D _Control;
		float4 _Control_ST;
		float4 _TerrainOffset;
		float _NormalScale;
		float _Parallax;
		sampler2D _Splat0,_Splat1,_Splat2,_Splat3;

		#ifdef _TERRAIN_NORMAL_MAP
			sampler2D _Normal0, _Normal1, _Normal2, _Normal3;
		#endif

		sampler2D _ParallaxMap3;

		#ifdef HEIGHTMAP
			sampler2D _Heightmap;
			half4 _Heightmap_TexelSize;
		#endif

		void SplatmapVert(inout appdata_full v, out Input data)
		{
			UNITY_INITIALIZE_OUTPUT(Input, data);
			data.tc_Control = TRANSFORM_TEX(v.texcoord, _Control);	// Need to manually transform uv here, as we choose not to use 'uv' prefix for this texcoord.
			v.vertex += _TerrainOffset;
		#if defined(HEIGHTMAP)
			v.texcoord.xy = (v.texcoord.xy * (_Heightmap_TexelSize.zw - 1) + 0.5) / _Heightmap_TexelSize.zw;

			float elevation = tex2Dlod(_Heightmap, v.texcoord);
			v.vertex.y += elevation;
			data.elevation = elevation * 3200 - 600;

			v.normal.x = elevation - tex2Dlod(_Heightmap, v.texcoord + float4(_Heightmap_TexelSize.x, 0, 0, 0));
			v.normal.y = elevation - tex2Dlod(_Heightmap, v.texcoord + float4(0, _Heightmap_TexelSize.y, 0, 0));
			v.normal.xy *= 450 * _NormalScale;
		#else
			data.elevation = v.vertex.y - 600.0;
		#endif

			float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
			posWorld.y = CompensateForEarthCurvature(posWorld + float4(unity_ObjectToWorld[0].w, 0.0, unity_ObjectToWorld[2].w, 0.0)).y;

			float4 pos = mul(UNITY_MATRIX_VP, posWorld);

		#ifdef _TERRAIN_NORMAL_MAP
			v.tangent.xyz = cross(v.normal, float3(0,0,1));
			v.tangent.w = -1;
		#endif
		}

		#ifdef TERRAIN_STANDARD_SHADER
		void SplatmapMix(Input IN, half4 defaultAlpha, out half4 splat_control, out half weight, out fixed4 mixedDiffuse, inout fixed3 mixedNormal)
		#else
		void SplatmapMix(Input IN, out half4 splat_control, out half weight, out fixed4 mixedDiffuse, inout fixed3 mixedNormal)
		#endif
		{
			splat_control = tex2D(_Control, IN.tc_Control);
			splat_control.a *= max(0.0, 1.0f - dot(splat_control, half4(1, 1, 1, 0)));

		#if !defined(DONT_USE_ELEVATION_DATA)
			half beach = saturate((3.5 - IN.elevation) * 0.08);
			splat_control.g += beach;
			splat_control.r = max(0.0, splat_control.r - beach);
		#endif

			weight = dot(splat_control, half4(1,1,1,1));

			#if !defined(SHADER_API_MOBILE) && defined(TERRAIN_SPLAT_ADDPASS)
				clip(weight == 0.0f ? -1 : 1);
			#endif

			// Normalize weights before lighting and restore weights in final modifier functions so that the overal
			// lighting result can be correctly weighted.

			if(weight > 1.0)
			{
				splat_control /= weight;
				weight = 1.0;
			}

			splat_control.b = 1.0 - weight;

			mixedDiffuse = 0.0f;
			#ifdef TERRAIN_STANDARD_SHADER
				mixedDiffuse += splat_control.r * tex2D(_Splat0, IN.uv2_Splat0)/* * half4(1.0, 1.0, 1.0, defaultAlpha.r)*/;
				mixedDiffuse += splat_control.g * tex2D(_Splat1, IN.uv2_Splat1)/* * half4(1.0, 1.0, 1.0, defaultAlpha.g)*/;
				mixedDiffuse += splat_control.b * tex2D(_Splat2, IN.uv2_Splat2)/* * half4(1.0, 1.0, 1.0, defaultAlpha.b)*/;
				mixedDiffuse += splat_control.a * tex2D(_Splat3, IN.uv2_Splat3)/* * half4(1.0, 1.0, 1.0, defaultAlpha.a)*/;
			#else
				mixedDiffuse += splat_control.r * tex2D(_Splat0, IN.uv2_Splat0);
				mixedDiffuse += splat_control.g * tex2D(_Splat1, IN.uv2_Splat1);
				mixedDiffuse += splat_control.b * tex2D(_Splat2, IN.uv2_Splat2);
				mixedDiffuse += splat_control.a * tex2D(_Splat3, IN.uv2_Splat3);
			#endif

			#ifdef _TERRAIN_NORMAL_MAP
				fixed4 nrm = 0.0f;
				nrm += splat_control.r * tex2D(_Normal0, IN.uv2_Splat0);
				nrm += splat_control.g * tex2D(_Normal1, IN.uv2_Splat1);
				nrm += splat_control.b * tex2D(_Normal2, IN.uv2_Splat2);
				nrm += splat_control.a * tex2D(_Normal3, IN.uv2_Splat3);
				//mixedNormal = UnpackScaleNormal(nrm, _NormalMapsIntensity);
				mixedNormal = UnpackNormal(nrm);
			#endif
		}

		#ifndef TERRAIN_SURFACE_OUTPUT
			#define TERRAIN_SURFACE_OUTPUT SurfaceOutput
		#endif

		void SplatmapFinalColor(Input IN, TERRAIN_SURFACE_OUTPUT o, inout fixed4 color)
		{
			color *= o.Alpha;
		}

		void SplatmapFinalPrepass(Input IN, TERRAIN_SURFACE_OUTPUT o, inout fixed4 normalSpec)
		{
			normalSpec *= o.Alpha;
		}

		void SplatmapFinalGBuffer(Input IN, TERRAIN_SURFACE_OUTPUT o, inout half4 diffuse, inout half4 specSmoothness, inout half4 normal, inout half4 emission)
		{
			diffuse.rgb *= o.Alpha;
			specSmoothness *= o.Alpha;
			normal.rgb *= o.Alpha;
			emission *= o.Alpha;
		}

		half _NoiseFrequency;
		half _NoiseIntensity;
		half _NoiseDistanceFactor;

		void surf (Input IN, inout SurfaceOutputStandard o) {
			half4 splat_control;
			half weight;
			fixed4 mixedDiffuse;

			half h = tex2D(_ParallaxMap3, IN.uv2_Splat3).g;
			float2 offset = ParallaxOffset1Step(h, _Parallax, IN.viewDir);
			IN.uv2_Splat3.xy += offset;

			half4 defaultSmoothness = half4(_Smoothness0, _Smoothness1, _Smoothness2, _Smoothness3);
			SplatmapMix(IN, defaultSmoothness, splat_control, weight, mixedDiffuse, o.Normal);
			o.Albedo = mixedDiffuse.rgb * _ColorMultiplier;
			
			half3 detailAlbedo = tex2D(_MainTex, IN.tc_Control);
			o.Albedo *= detailAlbedo * unity_ColorSpaceDouble.rgb;
			o.Alpha = 1.0;

			half4 detailMos = tex2D(_MetallicGlossMap, IN.tc_Control);
			o.Smoothness = detailMos.a;
			o.Metallic = detailMos.r;
			o.Occlusion *= detailMos.g;

			half noiseIntensity = (1.0 - exp(length(_WorldSpaceCameraPos - IN.worldPos) * -_NoiseDistanceFactor)) * _NoiseIntensity;

			float freq = _NoiseFrequency;
			float noise = 0.0;
			for (int i = 0; i < 2; ++i)
			{
				noise += Perlin2D(IN.worldPos.xz * freq) * noiseIntensity;
				freq *= 2.0;
				noiseIntensity *= 0.6;
			}

			if (noise < 0.0)
				o.Albedo *= 1.0 / (1.0 - noise);
			else
				o.Albedo *= 1.0 + noise;
			
			if (mixedDiffuse.a < 0.5)
				o.Smoothness = lerp(0.0, o.Smoothness, mixedDiffuse.a * 2.0);
			else
				o.Smoothness = lerp(o.Smoothness, 1.0, (mixedDiffuse.a - 0.5f) * 2.0);

			//o.Smoothness = lerp(o.Smoothness, 1.0, mixedDiffuse.a);
			//o.Metallic = dot(splat_control, half4(_Metallic0, _Metallic1, _Metallic2, _Metallic3)) + _Metallic4 * fifthTexIntensity;
		}
		ENDCG
	}

	Dependency "AddPassShader" = "Hidden/TerrainEngine/Splatmap/Standard-AddPass"
	Dependency "BaseMapShader" = "Hidden/TerrainEngine/Splatmap/Standard-Base"

	Fallback "Nature/Terrain/Diffuse"
}

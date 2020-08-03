// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "Standard (DWS)"
{
    Properties
    {
        _Color("Color", Color) = (1,1,1,1)
        _MainTex("Albedo", 2D) = "white" {}

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        _Glossiness("Smoothness", Range(0.0, 1.0)) = 0.5
        _GlossMapScale("Smoothness Scale", Range(0.0, 2.0)) = 1.0
        [Enum(Metallic Alpha,0,Albedo Alpha,1)] _SmoothnessTextureChannel ("Smoothness texture channel", Float) = 0

        [Gamma] _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _MetallicGlossMap("Metallic", 2D) = "white" {}

        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [ToggleOff] _GlossyReflections("Glossy Reflections", Float) = 1.0

        _BumpScale("Scale", Float) = 1.0
        _BumpMap("Normal Map", 2D) = "bump" {}

        _Parallax ("Height Scale", Range (0.005, 0.08)) = 0.02
        _ParallaxMap ("Height Map", 2D) = "black" {}

        _OcclusionStrength("Strength", Range(0.0, 1.0)) = 1.0
        _OcclusionMap("Occlusion", 2D) = "white" {}

        _EmissionColor("Color", Color) = (0,0,0)
        _EmissionMap("Emission", 2D) = "white" {}

        _DetailMask("Detail Mask", 2D) = "white" {}

        _DetailAlbedoMap("Detail Albedo x2", 2D) = "grey" {}
        _DetailNormalMapScale("Scale", Float) = 1.0
        _DetailNormalMap("Normal Map", 2D) = "bump" {}

		_DamageMask("", 2D) = "black" {}
		_DamageMap("", 2D) = "white" {}
		_DissolveMaskScale("Dissolve Mask Scale", Float) = 0.25

		[PerRendererData] _WetnessBiasScale("", Vector) = (0.0, 0.0, 0.0, 0.0)
		_WetnessMap("", 2D) = "white" {}

		_DamageMapPreferredResolution("", Float) = 4096
		_WetnessMapPreferredResolution("", Float) = 512

		[Enum(UV0,0,UV1,1)] _UVWetnessMap("UV Set for wetness map", Float) = 0

		[Enum(UV0,0,UV1,1)] _UVSec("UV Set for secondary textures", Float) = 0

			// Blending state
			[HideInInspector] _Mode("__mode", Float) = 0.0
			[HideInInspector] _SrcBlend("__src", Float) = 1.0
			[HideInInspector] _DstBlend("__dst", Float) = 0.0
			[HideInInspector] _ZWrite("__zw", Float) = 1.0
	}

		CGINCLUDE
#define UNITY_SETUP_BRDF_INPUT MetallicSetup
			ENDCG

		SubShader
		{
			Tags { "RenderType" = "Opaque" "PerformanceChecks" = "False" }


		Pass
        {
            Name "FORWARD SRP"
            Tags { "LightMode" = "ForwardSRP" }

            Blend 0 [_SrcBlend] [_DstBlend]
			BlendOp 0 Add, Add
			Blend 1 [_SrcBlend] [_DstBlend]
			BlendOp 1 Add, Add
            ZWrite [_ZWrite]
			ZTest LEqual

            CGPROGRAM
            #pragma target 4.5

            // -------------------------------------

            #pragma shader_feature _NORMALMAP
            #pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICGLOSSMAP
            #pragma shader_feature ___ _DETAIL_MULX2
            //#pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature _ _SPECULARHIGHLIGHTS_OFF
            //#pragma shader_feature _ _GLOSSYREFLECTIONS_OFF
            #pragma shader_feature _PARALLAXMAP
			#pragma shader_feature COMPENSATE_EARTH_CURVATURE_PER_VERTEX

			// EDIT START
			#pragma multi_compile _ _DISSOLVE _DAMAGE_MAP
			#pragma multi_compile _ _WETNESS_SUPPORT_ON
			#pragma multi_compile _ USE_CUSTOM_AMBIENT
			#pragma multi_compile __ DYNAMICLIGHTMAP_ON
			// EDIT END

			// fwdbase
			//#pragma multi_compile _ LIGHTPROBE_SH
			//#pragma multi_compile _ SHADOWS_SHADOWMASK
			#if !defined(DYNAMICLIGHTMAP_ON)
				//#define LIGHTMAP_ON 1
				//#define DIRLIGHTMAP_COMBINED 1
				#define LIGHTPROBE_SH 1
			#endif
			#if defined(USE_CUSTOM_AMBIENT) && !defined(DYNAMICLIGHTMAP_ON)
				#if !defined(LIGHTPROBE_SH)
					#define LIGHTPROBE_SH 1
				#endif
				#if defined(UNITY_LIGHT_PROBE_PROXY_VOLUME)
					#undef UNITY_INSTANCED_SH
				#endif
				#if defined(UNITY_LIGHT_PROBE_PROXY_VOLUME)
					#undef UNITY_LIGHT_PROBE_PROXY_VOLUME
				#endif
			#endif
			#define FOG_EXP2 1
			// end

            //#pragma multi_compile_fwdbase
            //#pragma multi_compile_fog
            #pragma multi_compile_instancing
            // Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
            //#pragma multi_compile _ LOD_FADE_CROSSFADE

			#define UNITY_HDR_ON 1

            #pragma vertex vertBase
            #pragma fragment fragForwardBaseSRP
            #include "UnityStandardCoreForward.cginc"

            ENDCG
        }
        // ------------------------------------------------------------------
        //  Shadow rendering pass
		Pass{
			Name "ShadowCaster"
			Tags { "LightMode" = "ShadowCaster" }

			ZWrite On ZTest LEqual

			CGPROGRAM
			#pragma target 3.0

			// -------------------------------------


			#pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature _METALLICGLOSSMAP
			#pragma shader_feature _PARALLAXMAP
			#pragma multi_compile_shadowcaster
			#pragma multi_compile_instancing
			// Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
			//#pragma multi_compile _ LOD_FADE_CROSSFADE

			// EDIT START
			#pragma multi_compile _ _DISSOLVE
			// EDIT END

			#define UNITY_HDR_ON 1

			#pragma vertex vertShadowCaster
			#pragma fragment fragShadowCaster

			#include "UnityStandardShadow.cginc"

			ENDCG
		}
			// ------------------------------------------------------------------
			//  Deferred pass
			Pass
		{
			Name "DEFERRED"
			Tags { "LightMode" = "Deferred" }

			ZWrite On
			ZTest LEqual

			CGPROGRAM
			#pragma target 4.5
			#pragma exclude_renderers nomrt

			// -------------------------------------

			#pragma shader_feature _NORMALMAP
			#pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature _EMISSION
			#pragma shader_feature _METALLICGLOSSMAP
			//#pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature _ _SPECULARHIGHLIGHTS_OFF
			#pragma shader_feature ___ _DETAIL_MULX2
			#pragma shader_feature _PARALLAXMAP
			#pragma shader_feature COMPENSATE_EARTH_CURVATURE_PER_VERTEX

			// EDIT START
			#pragma multi_compile _ _DISSOLVE _DAMAGE_MAP
			#pragma multi_compile _ _WETNESS_SUPPORT_ON
			#pragma multi_compile _ USE_CUSTOM_AMBIENT
			////#pragma multi_compile _ DIRLIGHTMAP_COMBINED
			//#pragma multi_compile _ DYNAMICLIGHTMAP_ON			// it's also inside multi_compile_prepassfinal
			//#pragma multi_compile _ LIGHTMAP_ON
			// EDIT END

			#define UNITY_HDR_ON 1

			// prepassfinal
			//#pragma multi_compile _ LIGHTPROBE_SH
			//#pragma multi_compile _ SHADOWS_SHADOWMASK
			//#if defined(DYNAMICLIGHTMAP_ON) || defined(LIGHTMAP_ON)
			//	#define DIRLIGHTMAP_COMBINED 1
			//#endif
			#if !defined(DYNAMICLIGHTMAP_ON)
				#define LIGHTPROBE_SH 1
			#endif
			#if defined(USE_CUSTOM_AMBIENT) && !defined(DYNAMICLIGHTMAP_ON)
				#if !defined(LIGHTPROBE_SH)
					#define LIGHTPROBE_SH 1
				#endif
				#if defined(UNITY_LIGHT_PROBE_PROXY_VOLUME)
					#undef UNITY_INSTANCED_SH
				#endif
				#if defined(UNITY_LIGHT_PROBE_PROXY_VOLUME)
					#undef UNITY_LIGHT_PROBE_PROXY_VOLUME
				#endif
			#endif
			// end

			#pragma multi_compile_prepassfinal			// BEWARE: with this setting disabled, shadow masking is not supported in this shader, non-directional lightmap modes are also not supported
			#pragma multi_compile_instancing
			// Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
			//#pragma multi_compile _ LOD_FADE_CROSSFADE

			#pragma vertex vertDeferred
			#pragma fragment fragDeferred

			#include "UnityStandardCore.cginc"

			ENDCG
		}

			// EDITS START

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

			#include "UnityStandardCore.cginc"
			ENDCG
		}

		// EDITS END

        // ------------------------------------------------------------------
        // Extracts information for lightmapping, GI (emission, albedo, ...)
        // This pass it not used during regular rendering.
        Pass
        {
            Name "META"
            Tags { "LightMode"="Meta" }

            Cull Off

            CGPROGRAM
            #pragma vertex vert_meta
            #pragma fragment frag_meta

            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICGLOSSMAP
            //#pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature ___ _DETAIL_MULX2
            #pragma shader_feature EDITOR_VISUALIZATION

			#ifndef UNITY_PASS_META
				#define UNITY_PASS_META
			#endif
			#define UNITY_HDR_ON 1

            #include "UnityStandardMeta.cginc"
            ENDCG
        }
    }

    /*SubShader
    {
        Tags { "RenderType"="Opaque" "PerformanceChecks"="False" }
        LOD 150

        // ------------------------------------------------------------------
        //  Base forward pass (directional light, emission, lightmaps, ...)
        Pass
        {
            Name "FORWARD"
            Tags { "LightMode" = "ForwardBase" }

            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]

            CGPROGRAM
            #pragma target 2.0

            #pragma shader_feature _NORMALMAP
            #pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICGLOSSMAP
            //#pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature _ _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature _ _GLOSSYREFLECTIONS_OFF
            // SM2.0: NOT SUPPORTED shader_feature ___ _DETAIL_MULX2
            // SM2.0: NOT SUPPORTED shader_feature _PARALLAXMAP

            #pragma skip_variants SHADOWS_SOFT DIRLIGHTMAP_COMBINED

            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog

            #pragma vertex vertBase
            #pragma fragment fragBase
            #include "UnityStandardCoreForward.cginc"

            ENDCG
        }
        // ------------------------------------------------------------------
        //  Additive forward pass (one light per pass)
        Pass
        {
            Name "FORWARD_DELTA"
            Tags { "LightMode" = "ForwardAdd" }
            Blend [_SrcBlend] One
            Fog { Color (0,0,0,0) } // in additive pass fog should be black
            ZWrite Off
            ZTest LEqual

            CGPROGRAM
            #pragma target 2.0

            #pragma shader_feature _NORMALMAP
            #pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _METALLICGLOSSMAP
            //#pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature _ _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature ___ _DETAIL_MULX2
            // SM2.0: NOT SUPPORTED shader_feature _PARALLAXMAP
            #pragma skip_variants SHADOWS_SOFT

            #pragma multi_compile_fwdadd_fullshadows
            #pragma multi_compile_fog

            #pragma vertex vertAdd
            #pragma fragment fragAdd
            #include "UnityStandardCoreForward.cginc"

            ENDCG
        }
        // ------------------------------------------------------------------
        //  Shadow rendering pass
        Pass {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On ZTest LEqual

            CGPROGRAM
            #pragma target 2.0

            #pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _METALLICGLOSSMAP
            #pragma skip_variants SHADOWS_SOFT
            #pragma multi_compile_shadowcaster

            #pragma vertex vertShadowCaster
            #pragma fragment fragShadowCaster

            #include "UnityStandardShadow.cginc"

            ENDCG
        }

        // ------------------------------------------------------------------
        // Extracts information for lightmapping, GI (emission, albedo, ...)
        // This pass it not used during regular rendering.
        Pass
        {
            Name "META"
            Tags { "LightMode"="Meta" }

            Cull Off

            CGPROGRAM
            #pragma vertex vert_meta
            #pragma fragment frag_meta

            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICGLOSSMAP
            //#pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature ___ _DETAIL_MULX2
            #pragma shader_feature EDITOR_VISUALIZATION

            #include "UnityStandardMeta.cginc"
            ENDCG
        }
    }*/


    //FallBack "VertexLit"
    CustomEditor "StandardDWSShaderGUI"
}

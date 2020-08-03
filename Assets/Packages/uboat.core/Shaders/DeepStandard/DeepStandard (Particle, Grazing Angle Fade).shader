// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "Standard (DWS, Particle, Grazing Angle Fade)"
{
    Properties
    {
        _Color("Color", Color) = (1,1,1,1)
        _MainTex("Albedo", 2D) = "white" {}

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        _Glossiness("Smoothness", Range(0.0, 1.0)) = 0.5
        _GlossMapScale("Smoothness Scale", Range(0.0, 1.0)) = 1.0
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

        _DistortionStrength("Strength", Float) = 1.0
        _DistortionBlend("Blend", Range(0.0, 1.0)) = 0.5

		_UnderwaterMaskFactors("Underwater Mask Factors", Vector) = (0, 0, 0, 0)

        _SoftParticlesNearFadeDistance("Soft Particles Near Fade", Float) = 0.0
        _SoftParticlesFarFadeDistance("Soft Particles Far Fade", Float) = 1.0
        _CameraNearFadeDistance("Camera Near Fade", Float) = 1.0
        _CameraFarFadeDistance("Camera Far Fade", Float) = 2.0

		_LightDesaturation("Light Desaturation", Range(0.0, 1.0)) = 0.0
		_LightingSoftness("Lighting Softness", Range(0.0, 1.0)) = 0.2

		_SubsurfaceScatteringColor("Subsurface Scattering Color", Color) = (0, 0, 0, 0)

        // Hidden properties
        [HideInInspector] _Mode ("__mode", Float) = 0.0
        [HideInInspector] _FlipbookMode ("__flipbookmode", Float) = 0.0
        [HideInInspector] _LightingEnabled ("__lightingenabled", Float) = 1.0
        [HideInInspector] _DistortionEnabled ("__distortionenabled", Float) = 0.0
        [HideInInspector] _EmissionEnabled ("__emissionenabled", Float) = 0.0
        [HideInInspector] _BlendOp ("__blendop", Float) = 0.0
		[HideInInspector] _StencilMode ("_StencilMode", Float) = 8
        [HideInInspector] _SrcBlend ("__src", Float) = 1.0
        [HideInInspector] _DstBlend ("__dst", Float) = 0.0
		[HideInInspector] _FogSrcBlend ("__fogsrc", Float) = 1.0
        [HideInInspector] _FogDstBlend ("__fogdst", Float) = 0.0
        [HideInInspector] _ZWrite ("__zw", Float) = 1.0
        [HideInInspector] _Cull ("__cull", Float) = 2.0
        [HideInInspector] _SoftParticlesEnabled ("__softparticlesenabled", Float) = 0.0
        [HideInInspector] _CameraFadingEnabled ("__camerafadingenabled", Float) = 0.0
        [HideInInspector] _SoftParticleFadeParams ("__softparticlefadeparams", Vector) = (0,0,0,0)
        [HideInInspector] _CameraFadeParams ("__camerafadeparams", Vector) = (0,0,0,0)
    }

    CGINCLUDE
        #define UNITY_SETUP_BRDF_INPUT MetallicSetup
    ENDCG

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "PerformanceChecks"="False" }

		Pass
        {
            Name "FORWARD SRP"
            Tags { "LightMode" = "ForwardSRP" }

            Blend 0 [_SrcBlend] [_DstBlend], OneMinusDstAlpha One
			BlendOp 0 Add, Add
			Blend 1 [_FogSrcBlend] [_FogDstBlend]
			BlendOp 1 Add, Add
            ZWrite [_ZWrite]
			Cull [_Cull]

			Stencil
			{
				Ref 2
				ReadMask 2
				Comp [_StencilMode]
				Pass keep
			}

            CGPROGRAM
            #pragma target 4.5

            // -------------------------------------

			//#pragma multi_compile __ SOFTPARTICLES_ON
			#pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON _ALPHAMODULATE_ON
			#pragma shader_feature _METALLICGLOSSMAP
			#pragma shader_feature _NORMALMAP
			#pragma shader_feature _EMISSION
			#pragma shader_feature _FADING_ON
			#pragma shader_feature _REQUIRE_UV2
			//#pragma shader_feature LIGHTPROBE_SH
			#pragma shader_feature _MASK_UNDERWATER
			#pragma shader_feature _DISABLE_LIGHTING
			#pragma multi_compile _ USE_CUSTOM_AMBIENT

			#define UNITY_HDR_ON 1
			#define _ANGULAR_FADING_ON 1

			#define LIGHTPROBE_SH 1
			#if defined(USE_CUSTOM_AMBIENT)
				#if defined(UNITY_LIGHT_PROBE_PROXY_VOLUME)
					#undef UNITY_INSTANCED_SH
				#endif
				#if defined(UNITY_LIGHT_PROBE_PROXY_VOLUME)
					#undef UNITY_LIGHT_PROBE_PROXY_VOLUME
				#endif
			#endif

            //#pragma multi_compile_instancing
            // Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
            //#pragma multi_compile _ LOD_FADE_CROSSFADE
			#pragma multi_compile_fog

            #pragma vertex vertForwardBase
            #pragma fragment fragForwardBaseSRP
            #include "UnityStandardParticles.cginc"

            ENDCG
        }
    }

    //FallBack "VertexLit"
    CustomEditor "StandardParticlesShaderGUI"
}

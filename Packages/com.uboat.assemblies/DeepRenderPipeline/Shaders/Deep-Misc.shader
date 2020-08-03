Shader "Hidden/Deep-Misc"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}

	HLSLINCLUDE

        #pragma exclude_renderers gles gles3 d3d11_9x
        #pragma target 4.5

        #include "Assets/Standard Assets/PostProcessing-2/Shaders/StdLib.hlsl"
        #include "Assets/Standard Assets/PostProcessing-2/Shaders/Builtins/Fog.hlsl"

        TEXTURE2D_SAMPLER2D(_CameraDepthTexture, sampler_CameraDepthTexture);
        TEXTURE2D_SAMPLER2D(_AmbientOcclusionTexture, sampler_AmbientOcclusionTexture);
        float3 _AOColor;

    ENDHLSL

	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		Pass
        {
			Name "SSAO Apply"
            Blend Zero OneMinusSrcColor, Zero OneMinusSrcAlpha
			
            HLSLPROGRAM

                #pragma vertex VertDefault
                #pragma fragment Frag

                struct Output
                {
                    float4 gbuffer0 : SV_Target0;
                    float4 gbuffer3 : SV_Target1;
                };

                Output Frag(VaryingsDefault i)
                {
                    float ao = 1.0 - SAMPLE_TEXTURE2D(_AmbientOcclusionTexture, sampler_AmbientOcclusionTexture, i.texcoordStereo).r;
                    Output o;
                    o.gbuffer0 = float4(0.0, 0.0, 0.0, ao);
                    o.gbuffer3 = float4(ao * _AOColor, 0.0);
                    return o;
                }

            ENDHLSL
        }
	}
}

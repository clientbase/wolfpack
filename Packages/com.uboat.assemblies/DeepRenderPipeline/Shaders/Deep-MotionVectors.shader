// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "Hidden/Deep-MotionVectors"
{
    SubShader
    {
        CGINCLUDE
        #include "UnityCG.cginc"

        // Object rendering things

#if defined(USING_STEREO_MATRICES)
        float4x4 _StereoNonJitteredVP[2];
        float4x4 _StereoPreviousVP[2];
#else
        float4x4 _NonJitteredViewProjMatrix;
        float4x4 _PrevViewProjMatrix;
#endif

        //Camera rendering things
        UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);

        struct CamMotionVectors
        {
            float4 pos : SV_POSITION;
            float2 uv : TEXCOORD0;
            float3 ray : TEXCOORD1;
            UNITY_VERTEX_OUTPUT_STEREO
        };

        struct CamMotionVectorsInput
        {
            float4 vertex : POSITION;
            float3 normal : NORMAL;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

		float4x4 _CameraInvViewProjection;

        CamMotionVectors VertMotionVectorsCamera(CamMotionVectorsInput v)
        {
            CamMotionVectors o;
            UNITY_SETUP_INSTANCE_ID(v);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
			o.pos = v.vertex;
            //o.pos = UnityObjectToClipPos(v.vertex);

#ifdef UNITY_HALF_TEXEL_OFFSET
            o.pos.xy += (_ScreenParams.zw - 1.0) * float2(-1, 1) * o.pos.w;
#endif
            o.uv = ComputeScreenPos(o.pos);
            // we know we are rendering a quad,
            // and the normal passed from C++ is the raw ray.
            o.ray = v.normal;
            return o;
        }

        inline half2 CalculateMotion(float rawDepth, float2 inUV, float4 worldPos)
        {
#if defined(USING_STEREO_MATRICES)
            float4 prevClipPos = mul(_StereoPreviousVP[unity_StereoEyeIndex], worldPos);
            float4 curClipPos = mul(_StereoNonJitteredVP[unity_StereoEyeIndex], worldPos);
#else
            float4 prevClipPos = mul(_PrevViewProjMatrix, worldPos);
            float4 curClipPos = mul(_NonJitteredViewProjMatrix, worldPos);
#endif
            float2 prevHPos = prevClipPos.xy / prevClipPos.w;
            float2 curHPos = curClipPos.xy / curClipPos.w;

            // V is the viewport position at this pixel in the range 0 to 1.
            float2 vPosPrev = (prevHPos.xy + 1.0f) / 2.0f;
            float2 vPosCur = (curHPos.xy + 1.0f) / 2.0f;
#if UNITY_UV_STARTS_AT_TOP
            vPosPrev.y = 1.0 - vPosPrev.y;
            vPosCur.y = 1.0 - vPosCur.y;
#endif
            return vPosCur - vPosPrev;
        }

        half4 FragMotionVectorsCamera(CamMotionVectors i) : SV_Target
        {
			float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
			half4 screenPos = half4(i.uv * 2 - 1, depth, 1);
			screenPos.y = -screenPos.y;

			float4 worldSpacePos = mul(_CameraInvViewProjection, screenPos);
			worldSpacePos /= worldSpacePos.w;

            return half4(CalculateMotion(depth, i.uv, worldSpacePos), 0, 1);
        }

        half4 FragMotionVectorsCameraWithDepth(CamMotionVectors i, out float outDepth : SV_Depth) : SV_Target
        {
            float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
            outDepth = depth;
            return half4(CalculateMotion(depth, i.uv, i.ray.xxxx), 0, 1);
        }
        ENDCG

        // 0 - Camera motion vectors
        Pass
        {
            ZTest Always
            Cull Off
            ZWrite Off

			Stencil
			{
				Ref [_CameraIndex]
				Comp Equal
			}

            CGPROGRAM
            #pragma vertex VertMotionVectorsCamera
            #pragma fragment FragMotionVectorsCamera
            ENDCG
        }

        // 1 - Camera motion vectors no stencil
        Pass
        {
            ZTest Always
            Cull Off
            ZWrite Off

			Stencil
			{
				Ref [_CameraIndex]
				Comp GEqual
			}

            CGPROGRAM
            #pragma vertex VertMotionVectorsCamera
            #pragma fragment FragMotionVectorsCamera
            ENDCG
        }
    }

    Fallback Off
}

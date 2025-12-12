Shader "Custom/PostProcess/OutlinePostProcess"
{
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "OutlinePost"
            ZTest Always ZWrite Off Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _OutlineColor;
            float _DepthThreshold;
            float _NormalThreshold;
            float _OutlineThickness;

            float GetLinearDepth(float2 uv)
            {
                float rawDepth = SampleSceneDepth(uv);
                return LinearEyeDepth(rawDepth, _ZBufferParams);
            }

            float DepthDiscontinuity(float2 uv, float2 texelSize, float centerDepth)
            {
                float threshold = centerDepth * _DepthThreshold * 0.1;
                float2 offsets[8] = {
                    float2(-1, -1), float2(0, -1), float2(1, -1),
                    float2(-1,  0),                float2(1,  0),
                    float2(-1,  1), float2(0,  1), float2(1,  1)
                };

                float maxDiff = 0;
                [unroll]
                for (int i = 0; i < 8; i++)
                {
                    float neighborDepth = GetLinearDepth(uv + offsets[i] * texelSize);
                    float diff = abs(centerDepth - neighborDepth);
                    maxDiff = max(maxDiff, diff);
                }

                return saturate(maxDiff / max(threshold, 0.001));
            }

            float NormalDiscontinuity(float2 uv, float2 texelSize)
            {
                float3 centerN = SampleSceneNormals(uv);

                float2 offsets[8] = {
                    float2(-1, -1), float2(0, -1), float2(1, -1),
                    float2(-1,  0),                float2(1,  0),
                    float2(-1,  1), float2(0,  1), float2(1,  1)
                };

                float minDot = 1.0;
                [unroll]
                for (int i = 0; i < 8; i++)
                {
                    float3 neighborN = SampleSceneNormals(uv + offsets[i] * texelSize);
                    float d = dot(centerN, neighborN);
                    minDot = min(minDot, d);
                }

                return saturate((1.0 - minDot) * 0.5 / max(_NormalThreshold, 0.01));
            }

            float SampleEdgeMulti(float2 uv, float2 texelSize, float centerDepth)
            {
                float2 subOffsets[4] = {
                    float2(-0.125, -0.375),
                    float2( 0.375, -0.125),
                    float2(-0.375,  0.125),
                    float2( 0.125,  0.375)
                };

                float edgeSum = 0;
                [unroll]
                for (int i = 0; i < 4; i++)
                {
                    float2 sampleUV = uv + subOffsets[i] * texelSize;
                    float sampleDepth = GetLinearDepth(sampleUV);

                    float depthEdge = DepthDiscontinuity(sampleUV, texelSize, sampleDepth);
                    float normalEdge = NormalDiscontinuity(sampleUV, texelSize);

                    float edge = max(depthEdge, normalEdge * (1.0 - depthEdge * 0.7));
                    edgeSum += edge;
                }

                return edgeSum * 0.25;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, input.texcoord);
                float2 texelSize = _BlitTexture_TexelSize.xy;

                float2 uv = input.texcoord;
                float2 sampleTexelSize = texelSize * _OutlineThickness;

                float rawDepth = SampleSceneDepth(uv);
                float linearDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

                if (rawDepth <= 0.0001)
                    return color;

                float edge = SampleEdgeMulti(uv, sampleTexelSize, linearDepth);

                edge = smoothstep(0.15, 0.6, edge);
                edge = pow(edge, 0.7);

                return lerp(color, _OutlineColor, edge * _OutlineColor.a);
            }
            ENDHLSL
        }
    }
}

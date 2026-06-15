import QtQuick
import qs.modules.common.functions as CF

ApiStrategy {
    readonly property string apiKeyEnvVarName: "API_KEY"
    readonly property string fileUriVarName: "BASE64_DATA"
    readonly property string fileMimeTypeVarName: "MIME_TYPE"
    readonly property string fileUriSubstitutionString: "{{ fileUriVarName }}"
    readonly property string fileMimeTypeSubstitutionString: "{{ fileMimeTypeVarName }}"

    property bool isReasoning: false

    function buildEndpoint(model: AiModel): string {
        return model.endpoint || "https://api.anthropic.com/v1/messages";
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let contents = messages.map(message => {
            const anthropicRole = (message.role === "assistant") ? "assistant" : "user";
            
            // Check if this message has attachments
            if (message.localFilePath && message.localFilePath.length > 0) {
                // If it is the user message with a local file path, we need to construct it as structured content block.
                // Note: QML-side localFilePath is trimmed of file protocol.
                // We'll return a placeholder block that finalizeScriptContent will replace.
                return {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": fileMimeTypeSubstitutionString,
                                "data": fileUriSubstitutionString
                            }
                        },
                        {
                            "type": "text",
                            "text": message.rawContent || "Visual search crop"
                        }
                    ]
                };
            }

            return {
                "role": anthropicRole,
                "content": message.rawContent
            };
        });

        // If there is a pendingFilePath (freshly attached in current request), attach it to the last user message
        if (filePath && filePath.length > 0) {
            let lastMsg = contents[contents.length - 1];
            if (lastMsg && lastMsg.role === "user") {
                lastMsg.content = [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": fileMimeTypeSubstitutionString,
                            "data": fileUriSubstitutionString
                        }
                    },
                    {
                        "type": "text",
                        "text": lastMsg.content || "Visual search crop"
                    }
                ];
            }
        }

        let baseData = {
            "model": model.model,
            "messages": contents,
            "system": systemPrompt,
            "stream": true,
            "max_tokens": 4096,
            "temperature": temperature
        };

        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "x-api-key: \$\{${apiKeyEnvVarName}\}" -H "anthropic-version: 2023-06-01"`;
    }

    function parseResponseLine(line, message) {
        let cleanData = line.trim();
        if (!cleanData.startsWith("data:")) {
            return {};
        }
        cleanData = cleanData.slice(5).trim();
        
        if (cleanData === "[DONE]") {
            return { finished: true };
        }

        try {
            const dataJson = JSON.parse(cleanData);
            
            if (dataJson.type === "content_block_delta") {
                let newContent = "";
                if (dataJson.delta?.type === "text_delta" && dataJson.delta?.text) {
                    if (isReasoning) {
                        isReasoning = false;
                        const endBlock = "\n\n</think>\n\n";
                        message.content += endBlock;
                        message.rawContent += endBlock;
                    }
                    newContent = dataJson.delta.text;
                } else if (dataJson.delta?.type === "thinking_delta" && dataJson.delta?.thinking) {
                    if (!isReasoning) {
                        isReasoning = true;
                        const startBlock = "\n\n<think>\n\n";
                        message.rawContent += startBlock;
                        message.content += startBlock;
                    }
                    newContent = dataJson.delta.thinking;
                }
                
                message.content += newContent;
                message.rawContent += newContent;

            } else if (dataJson.type === "content_block_start") {
                if (dataJson.content_block?.type === "thinking") {
                    isReasoning = true;
                    const startBlock = "\n\n<think>\n\n";
                    message.content += startBlock;
                    message.rawContent += startBlock;
                }
            } else if (dataJson.type === "content_block_stop") {
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n</think>\n\n";
                    message.content += endBlock;
                    message.rawContent += endBlock;
                }
            } else if (dataJson.type === "message_start") {
                if (dataJson.message?.usage) {
                    return {
                        tokenUsage: {
                            input: dataJson.message.usage.input_tokens ?? -1,
                            output: dataJson.message.usage.output_tokens ?? 0,
                            total: (dataJson.message.usage.input_tokens ?? 0) + (dataJson.message.usage.output_tokens ?? 0)
                        }
                    };
                }
            } else if (dataJson.type === "message_delta") {
                if (dataJson.usage) {
                    return {
                        tokenUsage: {
                            input: -1,
                            output: dataJson.usage.output_tokens ?? -1,
                            total: -1
                        }
                    };
                }
            } else if (dataJson.type === "message_stop" || dataJson.type === "error") {
                if (dataJson.error) {
                    const errorMsg = `**Error**: ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                    message.rawContent += errorMsg;
                    message.content += errorMsg;
                }
                return { finished: true };
            }
        } catch (e) {
            console.log("[AI] Anthropic: Could not parse line: ", e);
        }
        return {};
    }

    function onRequestFinished(message) {
        if (isReasoning) {
            isReasoning = false;
            const endBlock = "\n\n</think>\n\n";
            message.content += endBlock;
            message.rawContent += endBlock;
        }
        return { finished: true };
    }

    function reset() {
        isReasoning = false;
    }

    function buildScriptFileSetup(filePath) {
        const trimmedFilePath = CF.FileUtils.trimFileProtocol(filePath);
        let content = "";
        content += `IMAGE_PATH='${CF.StringUtils.shellSingleQuoteEscape(trimmedFilePath)}'\n`;
        content += `${fileMimeTypeVarName}=$(file -b --mime-type "$IMAGE_PATH")\n`;
        content += `BASE64_DATA=$(base64 -w 0 "$IMAGE_PATH")\n`;
        return content;
    }

    function finalizeScriptContent(scriptContent: string): string {
        return scriptContent.replace(fileMimeTypeSubstitutionString, `'"\$${fileMimeTypeVarName}"'`)
                            .replace(fileUriSubstitutionString, `'"\$${fileUriVarName}"'`);
    }
}

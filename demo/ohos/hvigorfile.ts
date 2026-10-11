import path from 'path'
import type { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { OhosHapContext, OhosPluginId, Target } from '@ohos/hvigor-ohos-plugin';
import { flutterHvigorPlugin } from 'flutter-hvigor-plugin';

const { ccrouterBuildPreflight } = require('./ccrouter-preflight')
const flutterProjectPath = path.dirname(__dirname)

function ccrouterHvigorPreflightPlugin(projectPath: string): HvigorPlugin {
    return {
        pluginId: 'ccrouter-hvigor-preflight',
        apply(rootNode: HvigorNode) {
            rootNode.subNodes(subNode => {
                if (subNode.getNodeName() !== 'entry') {
                    return
                }
                subNode.afterNodeEvaluate(node => {
                    const hapContext = node.getContext(
                        OhosPluginId.OHOS_HAP_PLUGIN
                    ) as OhosHapContext
                    if (!hapContext) {
                        return
                    }
                    hapContext.targets((target: Target) => {
                        const targetName = target.getTargetName()
                        node.registerTask({
                            name: `${targetName}@CCRouterPreflight`,
                            postDependencies: [`${targetName}@FlutterTask`],
                            run: () => ccrouterBuildPreflight(projectPath)
                        })
                    })
                })
            })
        }
    }
}

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[
        flutterHvigorPlugin(flutterProjectPath),
        ccrouterHvigorPreflightPlugin(flutterProjectPath)
    ]         /* Custom plugins to extend the functionality of Hvigor. */
}

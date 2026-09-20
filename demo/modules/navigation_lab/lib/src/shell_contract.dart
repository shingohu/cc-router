import 'package:ccrouter/ccrouter.dart';

const demoSingleShellId = 'demo_navigation_lab.single_shell';
const demoSingleShellOutlet = 'shell.content';

const demoWorkspaceShellId = 'demo_navigation_lab.workspace_shell';
const demoWorkspaceHomeOutlet = 'workspace.home';
const demoWorkspaceActivityOutlet = 'workspace.activity';
const demoWorkspaceProfileOutlet = 'workspace.profile';

final demoSingleShellDefinition = CCShellDefinition(
  shellId: demoSingleShellId,
  type: CCShellType.singleNavigator,
  outlets: const [demoSingleShellOutlet],
  initialOutlet: demoSingleShellOutlet,
);

final demoWorkspaceShellDefinition = CCShellDefinition(
  shellId: demoWorkspaceShellId,
  type: CCShellType.statefulBranches,
  outlets: const [
    demoWorkspaceHomeOutlet,
    demoWorkspaceActivityOutlet,
    demoWorkspaceProfileOutlet,
  ],
  initialOutlet: demoWorkspaceHomeOutlet,
);

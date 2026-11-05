import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/re_toolkit.dart';
import '../services/sandbox_service.dart';
import '../widgets/landscape_frame.dart';
import 're_toolkit_screen.dart';
import 'terminal_screen.dart';

/// 「工程」页：内置环境（终端）+ 逆向工具包入口。
///
/// 终端跑在 App 自带的 PRoot + Alpine 里，**不依赖 Termux**。
class EngineeringScreen extends StatefulWidget {
  const EngineeringScreen({super.key});

  @override
  State<EngineeringScreen> createState() => _EngineeringScreenState();
}

class _EngineeringScreenState extends State<EngineeringScreen> {
  final SandboxService _sandbox = SandboxService();
  SandboxStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await _sandbox.status();
    if (!mounted) return;
    setState(() => _status = s);
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    final s = await _sandbox.activate();
    if (!mounted) return;
    setState(() {
      _status = s;
      _busy = false;
    });
  }

  void _openTerminal([String? command]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalScreen(
          initialCommand: command,
          autoRun: command != null,
        ),
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    String? command,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              if (command != null) ...[
                const SizedBox(height: 12),
                Text('re_command_label'.tr(),
                    style: Theme.of(ctx).textTheme.labelSmall),
                const SizedBox(height: 4),
                SelectableText(
                  command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('termux_confirm_action'.tr()),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _installTools() async {
    final command = ReToolkit.installTools();
    final ok = await _confirm(
      title: 're_confirm_title'.tr(),
      body: 're_confirm_body'.tr(),
      command: command,
    );
    if (!ok || !mounted) return;
    _openTerminal(command);
  }

  Future<void> _activateSuite() async {
    final ok = await _confirm(
      title: 'env_suite_confirm_title'.tr(),
      body: 'env_suite_confirm_body'.tr(),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await _sandbox.activateBuildSuite();
    if (!mounted) return;
    setState(() => _busy = false);
    final String msg;
    if (r.ready) {
      msg = (r.alreadyReady ? 'env_suite_already' : 'env_suite_done').tr();
    } else {
      msg = r.message.isEmpty
          ? 'env_suite_failed'.tr()
          : '${'env_suite_failed'.tr()} ${r.message}';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: Text('engineering_title'.tr())),
      body: LandscapeFrame(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(title: 'env_section'.tr()),
            Text('env_intro'.tr()),
            const SizedBox(height: 12),
            if (st == null || _busy)
              const LinearProgressIndicator()
            else ...[
              _StatusRow(
                ok: st.installed,
                text: (st.installed ? 'env_status_ready' : 'env_status_missing')
                    .tr(),
              ),
              _StatusRow(
                ok: st.prootReady,
                text: (st.prootReady ? 'env_proot_ready' : 'env_proot_missing')
                    .tr(),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (st != null && !st.installed)
                  FilledButton(
                    onPressed: _busy ? null : _activate,
                    child: Text('terminal_activate'.tr()),
                  ),
                FilledButton.icon(
                  onPressed: () => _openTerminal(),
                  icon: const Icon(Icons.terminal, size: 16),
                  label: Text('open_terminal'.tr()),
                ),
                OutlinedButton(
                  onPressed: _refresh,
                  child: Text('env_recheck'.tr()),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _Section(title: 'env_tools_title'.tr()),
            Text('env_tools_note'.tr(), style: small),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _installTools,
              child: Text('env_tools_button'.tr()),
            ),
            const SizedBox(height: 24),
            _Section(title: 'env_suite_title'.tr()),
            Text('env_suite_note'.tr(), style: small),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _activateSuite,
              child: Text('env_suite_button'.tr()),
            ),
            const SizedBox(height: 24),
            _Section(title: 're_toolkit_title'.tr()),
            Text('re_intro'.tr()),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReToolkitScreen()),
              ),
              icon: const Icon(Icons.build_circle_outlined, size: 16),
              label: Text('re_toolkit_title'.tr()),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.ok, required this.text});
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.cancel,
                size: 18, color: ok ? Colors.green : Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

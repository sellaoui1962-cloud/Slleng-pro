import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sandbox_service.dart';

/// 内置终端：直接在 App 自带的 PRoot + Alpine 环境里执行命令，不依赖 Termux。
///
/// 能力边界（如实）：
///  · 非交互：命令启动后不能再输入（没有 stdin 通道），所以 vim / top / 要求输入的程序不能用；
///  · 没有「停止」按钮：原生通道没有取消接口，命令只会跑完或在超时后结束；
///  · 目录用「命令后打印 pwd」的办法在命令之间记住，所以 `cd` 有效，但环境变量不会保留。
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, this.initialCommand, this.autoRun = false});

  /// 预填的命令。
  final String? initialCommand;

  /// 为 true 时进入页面后立刻执行 [initialCommand]。
  /// 只有调用方已经把**完整命令**展示给用户并得到确认后才可以设为 true。
  final bool autoRun;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

enum _Kind { input, out, err, info }

class _Line {
  _Line(this.text, this.kind);
  String text;
  final _Kind kind;
}

class _TerminalScreenState extends State<TerminalScreen> {
  static const _marker = '__HCWD__';
  static const _bg = Color(0xFF0B0B12);
  static const _maxChars = 200000;
  static const _timeoutMs = 600000;

  final SandboxService _sandbox = SandboxService();
  final List<_Line> _lines = <_Line>[];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final List<String> _history = <String>[];
  int _histIdx = 0;
  String _cwd = '/workspace';
  bool _running = false;
  bool _activating = false;
  bool _autoStarted = false;
  SandboxStatus? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    // 不调用 _sandbox.dispose()：输出流是全 App 共享的。
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final s = await _sandbox.status();
    if (!mounted) return;
    setState(() => _status = s);
    final cmd = widget.initialCommand;
    if (cmd != null && !_autoStarted) {
      _autoStarted = true;
      _input.text = cmd;
      if (widget.autoRun && s.installed) {
        unawaited(_run(cmd));
      }
    }
  }

  Future<void> _activate() async {
    setState(() => _activating = true);
    final s = await _sandbox.activate();
    if (!mounted) return;
    setState(() {
      _status = s;
      _activating = false;
    });
    _push(
      '${(s.installed ? 'terminal_env_ready' : 'terminal_env_failed').tr()}\n',
      _Kind.info,
    );
    final cmd = widget.initialCommand;
    if (s.installed && widget.autoRun && cmd != null && _lines.isNotEmpty) {
      unawaited(_run(cmd));
    }
  }

  void _push(String text, _Kind kind) {
    if (text.isEmpty || !mounted) return;
    setState(() {
      final needsBreak = (kind == _Kind.input || kind == _Kind.info) &&
          _lines.isNotEmpty &&
          !_lines.last.text.endsWith('\n');
      if (needsBreak) _lines.last.text += '\n';
      if (kind != _Kind.input &&
          _lines.isNotEmpty &&
          _lines.last.kind == kind) {
        _lines.last.text += text;
      } else {
        _lines.add(_Line(text, kind));
      }
      var total = 0;
      for (final l in _lines) {
        total += l.text.length;
      }
      while (total > _maxChars && _lines.length > 1) {
        total -= _lines.removeAt(0).text.length;
      }
    });
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _run(String raw) async {
    final cmd = raw.trim();
    if (cmd.isEmpty || _running) return;
    _history.add(cmd);
    _histIdx = _history.length;
    _input.clear();
    _push('$_cwd \$ $cmd\n', _Kind.input);
    if (cmd == 'clear') {
      setState(_lines.clear);
      return;
    }
    final st = _status ?? await _sandbox.status();
    if (!mounted) return;
    if (!st.installed) {
      setState(() => _status = st);
      _push('${'terminal_env_required'.tr()}\n', _Kind.info);
      return;
    }
    setState(() => _running = true);
    try {
      await _exec(cmd);
    } finally {
      if (mounted) {
        setState(() => _running = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.requestFocus();
        });
      }
    }
  }

  Future<void> _exec(String cmd) async {
    // 命令之后多打印一行 pwd，用来在命令之间记住当前目录；退出码原样保留。
    final wrapped = '$cmd\n'
        '__hrc=\$?\n'
        'printf "\\n$_marker%s\\n" "\$(pwd)"\n'
        'exit \$__hrc';

    String? id;
    final bufOut = <SandboxOutputChunk>[];
    final bufDone = <SandboxExecDone>[];
    final bufErr = <SandboxExecError>[];
    final finished = Completer<void>();
    var pending = '';
    var markerSeen = false;
    var gotAny = false;
    final tail = StringBuffer();

    void feedOut(String chunk) {
      if (markerSeen) {
        tail.write(chunk);
        return;
      }
      pending += chunk;
      final i = pending.indexOf(_marker);
      if (i >= 0) {
        markerSeen = true;
        var visible = pending.substring(0, i);
        if (visible.endsWith('\n')) {
          visible = visible.substring(0, visible.length - 1);
        }
        tail.write(pending.substring(i + _marker.length));
        pending = '';
        _push(visible, _Kind.out);
      } else {
        // 标记可能被切在两个片段之间：留住末尾几个字符，等下一片段再判断。
        final keep = _marker.length - 1;
        if (pending.length > keep) {
          _push(pending.substring(0, pending.length - keep), _Kind.out);
          pending = pending.substring(pending.length - keep);
        }
      }
    }

    void feed(SandboxOutputChunk c) {
      if (c.isProgress) return;
      gotAny = true;
      if (c.isStderr) {
        _push(c.chunk, _Kind.err);
      } else {
        feedOut(c.chunk);
      }
    }

    void onDone(SandboxExecDone d) {
      final r = d.result;
      if (!gotAny) {
        // 流式通道什么都没送到：退回到最终结果，避免界面空白。
        if (r.stdout.isNotEmpty) feedOut(r.stdout);
        if (r.stderr.isNotEmpty) _push(r.stderr, _Kind.err);
      }
      if (!markerSeen && pending.isNotEmpty) {
        _push(pending, _Kind.out);
        pending = '';
      }
      if (markerSeen) {
        final line = tail.toString().split('\n').first.trim();
        if (line.startsWith('/') && mounted) setState(() => _cwd = line);
      }
      if (r.timedOut) {
        _push('${'terminal_timed_out'.tr()}\n', _Kind.info);
      } else if (r.cancelled) {
        _push('${'terminal_cancelled'.tr()}\n', _Kind.info);
      } else if (r.exitCode != 0) {
        _push(
          '${'terminal_exit_code'.tr(namedArgs: {'code': '${r.exitCode}'})}\n',
          _Kind.info,
        );
      }
      if (r.truncated) {
        _push('${'terminal_truncated'.tr()}\n', _Kind.info);
      }
      if (!finished.isCompleted) finished.complete();
    }

    void onErr(SandboxExecError e) {
      _push(
        '${'terminal_sandbox_error'.tr(namedArgs: {'message': e.message})}\n',
        _Kind.err,
      );
      if (!finished.isCompleted) finished.complete();
    }

    // 先订阅再提交：命令可能在 execute 返回之前就已经输出；id 未知时先缓存。
    final subs = <StreamSubscription<dynamic>>[
      _sandbox.outputStream.listen((c) {
        if (id == null) {
          bufOut.add(c);
        } else if (c.id == id) {
          feed(c);
        }
      }),
      _sandbox.doneStream.listen((d) {
        if (id == null) {
          bufDone.add(d);
        } else if (d.id == id) {
          onDone(d);
        }
      }),
      _sandbox.errorStream.listen((e) {
        if (id == null) {
          bufErr.add(e);
        } else if (e.id == id) {
          onErr(e);
        }
      }),
    ];

    final sub = await _sandbox.execute(
      wrapped,
      workdir: _cwd,
      timeoutMs: _timeoutMs,
    );
    if (!sub.ok) {
      for (final s in subs) {
        await s.cancel();
      }
      _push(
        '${'terminal_submit_failed'.tr(namedArgs: {'error': sub.error ?? ''})}\n',
        _Kind.err,
      );
      return;
    }
    id = sub.id;
    for (final c in bufOut) {
      if (c.id == id) feed(c);
    }
    for (final d in bufDone) {
      if (d.id == id) onDone(d);
    }
    for (final e in bufErr) {
      if (e.id == id) onErr(e);
    }
    try {
      await finished.future
          .timeout(const Duration(milliseconds: _timeoutMs + 15000));
    } on TimeoutException {
      _push('${'terminal_wait_timeout'.tr()}\n', _Kind.info);
    }
    for (final s in subs) {
      await s.cancel();
    }
  }

  void _histMove(int delta) {
    if (_history.isEmpty) return;
    var n = _histIdx + delta;
    if (n < 0) n = 0;
    if (n > _history.length) n = _history.length;
    _histIdx = n;
    _input.text = n == _history.length ? '' : _history[n];
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(
      ClipboardData(text: _lines.map((l) => l.text).join()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('message_copied'.tr())));
  }

  Color _color(_Kind k) => switch (k) {
        _Kind.input => const Color(0xFFA78BFA),
        _Kind.out => const Color(0xFFE5E7EB),
        _Kind.err => const Color(0xFFF87171),
        _Kind.info => const Color(0xFF9CA3AF),
      };

  TextStyle _style(Color c) =>
      TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.35, color: c);

  Widget _banner() => Container(
        width: double.infinity,
        color: const Color(0xFF1E1B3A),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text('terminal_env_banner'.tr(),
                  style: const TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _activating ? null : _activate,
              child: Text(_activating
                  ? 'terminal_activating'.tr()
                  : 'terminal_activate'.tr()),
            ),
          ],
        ),
      );

  Widget _output() => Directionality(
        textDirection: TextDirection.ltr,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(10),
          itemCount: _lines.isEmpty ? 1 : _lines.length,
          itemBuilder: (_, i) {
            if (_lines.isEmpty) {
              return Text('terminal_note'.tr(),
                  style: _style(const Color(0xFF9CA3AF)));
            }
            final l = _lines[i];
            return SelectableText(l.text, style: _style(_color(l.kind)));
          },
        ),
      );

  Widget _inputBar() => Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: const Color(0xFF15151F),
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white70),
                onPressed: () => _histMove(-1),
              ),
              IconButton(
                icon:
                    const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                onPressed: () => _histMove(1),
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  enabled: !_running,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _run,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 14, color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    prefixText: '$_cwd \$ ',
                    prefixStyle: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        color: Color(0xFFA78BFA)),
                    hintText: 'terminal_hint'.tr(),
                    hintStyle: const TextStyle(color: Colors.white38),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow, color: Color(0xFFA78BFA)),
                onPressed: _running ? null : () => _run(_input.text),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final st = _status;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text('terminal_title'.tr()),
        actions: [
          IconButton(
            tooltip: 'terminal_copy'.tr(),
            icon: const Icon(Icons.copy_all),
            onPressed: _copyAll,
          ),
          IconButton(
            tooltip: 'terminal_clear'.tr(),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => setState(_lines.clear),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_running) const LinearProgressIndicator(minHeight: 2),
            if (st != null && !st.installed) _banner(),
            Expanded(child: _output()),
            _inputBar(),
          ],
        ),
      ),
    );
  }
}

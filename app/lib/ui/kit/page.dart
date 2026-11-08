/// Page scaffolds: a tab page with an editorial header that condenses into
/// a top bar on scroll, and a pushed sub-page with a back button.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:openwear/ui/kit/basics.dart';
import 'package:openwear/ui/theme.dart';

/// Root page of a tab.
class TabPage extends StatefulWidget {
  const TabPage({
    super.key,
    required this.title,
    required this.children,
    this.eyebrow,
    this.trailing,
    this.onRefresh,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;
  final List<Widget> children;

  /// Pull-to-refresh when set.
  final Future<void> Function()? onRefresh;

  @override
  State<TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<TabPage> {
  final _scroll = ScrollController();
  final _born = DateTime.now();
  bool _condensed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final c = _scroll.offset > 64;
      if (c != _condensed) setState(() => _condensed = c);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final eyebrow = widget.eyebrow;
    final list = ListView(
      controller: _scroll,
      // Keep nearby cards alive so scrolling back does not rebuild them.
      scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.l,
        Space.gutter,
        Space.xxl,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (eyebrow != null) ...[
                    Eyebrow(eyebrow),
                    const SizedBox(height: Space.s),
                  ],
                  Text(widget.title, style: T.title.copyWith(color: p.text)),
                ],
              ),
            ),
            ?widget.trailing,
          ],
        ),
        const SizedBox(height: Space.xl),
        for (var i = 0; i < widget.children.length; i++)
          Reveal(index: i, child: widget.children[i]),
      ],
    );
    final refresh = widget.onRefresh;
    return ColoredBox(
      color: p.background,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            refresh == null
                ? EntranceScope(born: _born, child: list)
                : RefreshIndicator(
                    onRefresh: refresh,
                    color: p.accent,
                    backgroundColor: p.surface,
                    child: EntranceScope(born: _born, child: list),
                  ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                ignoring: !_condensed,
                child: AnimatedOpacity(
                  opacity: _condensed ? 1 : 0,
                  duration: Motion.quick,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.background,
                      border: Border(bottom: BorderSide(color: p.line)),
                    ),
                    child: Text(widget.title, style: T.bodyStrong),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pushed page: back arrow, title and a padded scrolling body.
class SubPage extends StatefulWidget {
  const SubPage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.s,
      Space.gutter,
      Space.xxl,
    ),
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final EdgeInsets padding;

  @override
  State<SubPage> createState() => _SubPageState();
}

class _SubPageState extends State<SubPage> {
  final _born = DateTime.now();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: subPageBar(context, widget.title, actions: widget.actions),
    body: EntranceScope(
      born: _born,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
        padding: widget.padding,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            Reveal(index: i, child: widget.children[i]),
        ],
      ),
    ),
  );
}

/// App bar for pushed pages, with a hairline underneath.
PreferredSizeWidget subPageBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
}) {
  final p = Palette.of(context);
  return AppBar(
    title: Text(title),
    actions: actions,
    leading: Navigator.of(context).canPop()
        ? IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          )
        : null,
    shape: Border(bottom: BorderSide(color: p.line)),
  );
}

/// Pushes [page] with the theme's page transition.
Future<void> push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// Heading above a group of content.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.m),
    child: Row(
      children: [
        Expanded(child: Eyebrow(text)),
        ?trailing,
      ],
    ),
  );
}

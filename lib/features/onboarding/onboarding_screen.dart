/// The three-page introduction.
///
/// It explains the personal-baseline idea before asking for anything, because that
/// idea is the reason the app asks for eight sessions before it says much. A user
/// who does not know that will conclude it is broken and stop.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';

/// A swipeable three-page explanation, ending at sign-in.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next(int pageCount) {
    if (_page >= pageCount - 1) {
      context.go(Routes.login);
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    final pages = <({IconData icon, String title, String body})>[
      (
        icon: Icons.timer_outlined,
        title: text.onboardingTitle1,
        body: text.onboardingBody1,
      ),
      (
        icon: Icons.person_outline,
        title: text.onboardingTitle2,
        body: text.onboardingBody2,
      ),
      (
        icon: Icons.lock_outline,
        title: text.onboardingTitle3,
        body: text.onboardingBody3,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 8),
                child: TextButton(
                  onPressed: () => context.go(Routes.login),
                  child: Text(text.skip),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (page) => setState(() => _page = page),
                itemCount: pages.length,
                itemBuilder: (context, index) => _OnboardingPage(
                  icon: pages[index].icon,
                  title: pages[index].title,
                  body: pages[index].body,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(kPagePadding),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? context.colors.primary
                                : context.colors.outlineVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  PrimaryButton(
                    label: _page == pages.length - 1
                        ? text.continueAction
                        : text.next,
                    onPressed: () => _next(pages.length),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.colors.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 36,
              color: context.colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            title,
            style: context.texts.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: context.texts.bodyLarge?.copyWith(
              color: context.colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

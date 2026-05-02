import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import 'home_screen_new.dart';
import 'subscription_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final _screens = const [
    HomeScreenNew(),
    SubscriptionScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildNewNavBar(),
    );
  }

  Widget _buildNewNavBar() {
    return Container(
      height: 92,
      decoration: const BoxDecoration(
        color: Color(0xFF06081A),
        border: Border(
          top: BorderSide(
            color: Color(0xFF0F1628),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildBottomBarItem(
              assetPath: _currentIndex == 0
                  ? 'bottombar_newicons/vpn_active.svg'
                  : 'bottombar_newicons/vpn_default.svg',
              onTap: () => setState(() => _currentIndex = 0),
            ),
            _buildBottomBarItem(
              assetPath: _currentIndex == 1
                  ? 'bottombar_newicons/podpiska_active.svg'
                  : 'bottombar_newicons/podpiska_default.svg',
              onTap: () => setState(() => _currentIndex = 1),
            ),
            _buildBottomBarItem(
              assetPath: _currentIndex == 2
                  ? 'bottombar_newicons/profile_active.svg'
                  : 'bottombar_newicons/profile_default.svg',
              onTap: () => setState(() => _currentIndex = 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBarItem({
    required String assetPath,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 129,
        height: double.infinity,
        child: Center(
          child: SvgPicture.asset(
            assetPath,
            width: 129,
            height: 64,
          ),
        ),
      ),
    );
  }
}

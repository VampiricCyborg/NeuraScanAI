import 'package:flutter/material.dart';

void main() {
  runApp(const NeuroScanApp());
}

class NeuroScanApp extends StatelessWidget {
  const NeuroScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroScan AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF146C7A)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F9FB),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF146C7A), Color(0xFF21D3C3)],
                    ),
                  ),
                  child: const Icon(Icons.psychology_alt, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 20),
                const Text(
                  'NeuroScan AI',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF0F2342)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Intelligent Behavioral Screening for\nNeurological Risk Analysis',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Color(0xFF62748B), height: 1.5),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF146C7A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
                    },
                    child: const Text('Begin Screening'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Research prototype — not a diagnostic medical device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF62748B)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int index = 0;
  final pages = const [
    _OnboardingPage(
      title: 'Your Behavioral Fingerprint',
      description: 'NeuroScan establishes a personal baseline from cognitive, speech, motor and interaction patterns.',
    ),
    _OnboardingPage(
      title: 'Track Changes Over Time',
      description: 'Future assessments can be compared against your own previous performance rather than relying only on population averages.',
    ),
    _OnboardingPage(
      title: 'Understand the Signals',
      description: 'NeuroScan provides an explainable breakdown showing which behavioral domains contributed to the screening result.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final page = pages[index];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Onboarding', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1.2)),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F7F8),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.psychology, color: Color(0xFF146C7A), size: 36),
                    ),
                    const SizedBox(height: 24),
                    Text(page.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0F2342))),
                    const SizedBox(height: 12),
                    Text(page.description, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Color(0xFF62748B), height: 1.6)),
                    const SizedBox(height: 28),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(pages.length, (i) => Container(margin: const EdgeInsets.symmetric(horizontal: 4), width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: i == index ? const Color(0xFF146C7A) : const Color(0xFFDDE7EC)))))
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF146C7A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    if (index < pages.length - 1) {
                      setState(() => index += 1);
                    } else {
                      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DashboardScreen()));
                    }
                  },
                  child: Text(index < pages.length - 1 ? 'Continue' : 'Open Dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final String title;
  final String description;
  const _OnboardingPage({required this.title, required this.description});
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Good morning', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF146C7A), letterSpacing: 1.2)),
              const SizedBox(height: 4),
              const Text('NeuroScan AI', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF0F2342))),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Neurological Wellness Snapshot', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  const Text('Current Screening Status', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF0F2342))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFFE8F8F0), borderRadius: BorderRadius.circular(999)),
                    child: const Text('LOW BEHAVIORAL DEVIATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF2E8B57))),
                  ),
                  const SizedBox(height: 10),
                  const Text('Your recent behavioral indicators remain close to your established baseline.', style: TextStyle(fontSize: 14, color: Color(0xFF62748B), height: 1.5)),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.1,
                    physics: const NeverScrollableScrollPhysics(),
                    children: const [
                      _DomainCard(label: 'Cognitive', value: '92 / 100', status: 'Stable'),
                      _DomainCard(label: 'Speech', value: '88 / 100', status: 'Stable'),
                      _DomainCard(label: 'Motor', value: '91 / 100', status: 'Stable'),
                      _DomainCard(label: 'Interaction', value: '86 / 100', status: 'Minor variation'),
                    ],
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF146C7A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AssessmentListScreen()));
                  },
                  child: const Text('Start Quick Scan'),
                ),
              ),
              const SizedBox(height: 18),
              const _BaselineCard(),
              const SizedBox(height: 16),
              const _ActivityCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DomainCard extends StatelessWidget {
  final String label;
  final String value;
  final String status;
  const _DomainCard({required this.label, required this.value, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF0F8FA), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFDDE7EC))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF62748B))),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F2342))),
        const SizedBox(height: 6),
        Text(status, style: const TextStyle(fontSize: 12, color: Color(0xFF146C7A), fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _BaselineCard extends StatelessWidget {
  const _BaselineCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFDDE7EC))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Baseline Progress', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F2342))),
        const SizedBox(height: 6),
        const Text('12 sessions recorded', style: TextStyle(fontSize: 14, color: Color(0xFF62748B))),
        const SizedBox(height: 4),
        const Text('Baseline confidence: 82%', style: TextStyle(fontSize: 14, color: Color(0xFF62748B))),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: 0.82, minHeight: 10, backgroundColor: const Color(0xFFF0F8FA), color: const Color(0xFF146C7A))),
      ]),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFDDE7EC))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Recent Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F2342))),
        const SizedBox(height: 10),
        _ActivityRow(title: 'Memory Assessment', time: '3 days ago', note: 'Normal variation'),
        const SizedBox(height: 8),
        _ActivityRow(title: 'Speech Assessment', time: '5 days ago', note: 'Stable'),
        const SizedBox(height: 8),
        _ActivityRow(title: 'Motor Assessment', time: '7 days ago', note: 'Stable'),
      ]),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final String title;
  final String time;
  final String note;
  const _ActivityRow({required this.title, required this.time, required this.note});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F2342))),
        Text(time, style: const TextStyle(fontSize: 12, color: Color(0xFF62748B))),
      ]),
      Text(note, style: const TextStyle(fontSize: 12, color: Color(0xFF146C7A), fontWeight: FontWeight.w600)),
    ]);
  }
}

class AssessmentListScreen extends StatelessWidget {
  const AssessmentListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final assessments = [
      _AssessmentItem(title: 'Memory Recall', subtitle: 'Tests short-term recall', duration: '~45 sec'),
      _AssessmentItem(title: 'Reaction Time', subtitle: 'Measures response consistency', duration: '~30 sec'),
      _AssessmentItem(title: 'Speech Analysis', subtitle: 'Analyzes speech characteristics', duration: '~45 sec'),
      _AssessmentItem(title: 'Motor Control', subtitle: 'Measures tracing stability', duration: '~30 sec'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Quick NeuroScan')), 
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Complete four short behavioral assessments.', style: TextStyle(fontSize: 15, color: Color(0xFF62748B))),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFDDE7EC))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Progress', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F2342))),
                const SizedBox(height: 8),
                const Text('0 / 4 assessments completed', style: TextStyle(fontSize: 14, color: Color(0xFF62748B))),
                const SizedBox(height: 10),
                ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: 0.0, minHeight: 10, backgroundColor: const Color(0xFFF0F8FA), color: const Color(0xFF146C7A))),
              ]),
            ),
            const SizedBox(height: 18),
            Expanded(child: ListView.separated(itemCount: assessments.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, index) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF0F8FA), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFDDE7EC))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(assessments[index].title, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F2342))), Text(assessments[index].subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF62748B))), Text(assessments[index].duration, style: const TextStyle(fontSize: 12, color: Color(0xFF62748B)))]), const Text('Pending', style: TextStyle(fontSize: 12, color: Color(0xFF62748B)))]))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MemoryAssessmentScreen())), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF146C7A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('Start Assessment'))),
          ]),
        ),
      ),
    );
  }
}

class _AssessmentItem {
  final String title;
  final String subtitle;
  final String duration;
  const _AssessmentItem({required this.title, required this.subtitle, required this.duration});
}

class MemoryAssessmentScreen extends StatefulWidget {
  const MemoryAssessmentScreen({super.key});

  @override
  State<MemoryAssessmentScreen> createState() => _MemoryAssessmentScreenState();
}

class _MemoryAssessmentScreenState extends State<MemoryAssessmentScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _showWords = true;
  int _secondsLeft = 10;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 1), _tick);
  }

  void _tick() {
    if (!mounted) return;
    if (_secondsLeft <= 1) {
      setState(() => _showWords = false);
      return;
    }
    setState(() => _secondsLeft -= 1);
    Future.delayed(const Duration(seconds: 1), _tick);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory Recall')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Memorize the following words. They will disappear shortly.', style: TextStyle(fontSize: 15, color: Color(0xFF62748B))),
            const SizedBox(height: 16),
            if (_showWords)
              Wrap(spacing: 10, runSpacing: 10, children: const [
                Chip(label: Text('RIVER')),
                Chip(label: Text('APPLE')),
                Chip(label: Text('CHAIR')),
                Chip(label: Text('CLOUD')),
                Chip(label: Text('TRAIN')),
              ]),
            const SizedBox(height: 20),
            Text('$_secondsLeft seconds', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF0F2342))),
            const SizedBox(height: 12),
            Text(_showWords ? 'The words will be hidden after the countdown.' : 'Enter as many words as you remember.', style: const TextStyle(fontSize: 14, color: Color(0xFF62748B))),
            const SizedBox(height: 20),
            TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Type words you remember', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReactionAssessmentScreen())); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF146C7A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('Submit'))),
          ]),
        ),
      ),
    );
  }
}

class ReactionAssessmentScreen extends StatefulWidget {
  const ReactionAssessmentScreen({super.key});

  @override
  State<ReactionAssessmentScreen> createState() => _ReactionAssessmentScreenState();
}

class _ReactionAssessmentScreenState extends State<ReactionAssessmentScreen> {
  bool _ready = false;
  int _round = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reaction Response')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Tap the screen as soon as the circle changes.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Color(0xFF62748B))),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                setState(() {
                  _round += 1;
                  _ready = false;
                });
                if (_round >= 5) {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpeechAssessmentScreen()));
                } else {
                  Future.delayed(const Duration(milliseconds: 800), () {
                    if (mounted) {
                      setState(() => _ready = true);
                    }
                  });
                }
              },
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: _ready ? [const Color(0xFF2E8B57), const Color(0xFF52C06C)] : [const Color(0xFF6C7A89), const Color(0xFF92A7B6)])),
                child: Center(child: Text(_ready ? 'Tap Now' : '$_round/5', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white))),
              ),
            ),
            const SizedBox(height: 18),
            const Text('A randomized delay will be introduced before the circle turns ready.', style: TextStyle(fontSize: 14, color: Color(0xFF62748B))),
          ]),
        ),
      ),
    );
  }
}

class SpeechAssessmentScreen extends StatelessWidget {
  const SpeechAssessmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speech Pattern Assessment')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Speak naturally for 15 seconds about what you did yesterday.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Color(0xFF62748B))),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MotorAssessmentScreen())), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF146C7A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('Start Recording')),
          ]),
        ),
      ),
    );
  }
}

class MotorAssessmentScreen extends StatefulWidget {
  const MotorAssessmentScreen({super.key});

  @override
  State<MotorAssessmentScreen> createState() => _MotorAssessmentScreenState();
}

class _MotorAssessmentScreenState extends State<MotorAssessmentScreen> {
  final List<Offset> _points = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Motor Stability Test')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Text('Trace the spiral slowly and stay as close to the guide as possible.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Color(0xFF62748B))),
            const SizedBox(height: 16),
            Expanded(
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _points.add(details.localPosition);
                  });
                },
                child: CustomPaint(painter: _SpiralPainter(points: _points), size: const Size(double.infinity, double.infinity)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResultsScreen())), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF146C7A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('Complete Motor Test')),
          ]),
        ),
      ),
    );
  }
}

class _SpiralPainter extends CustomPainter {
  final List<Offset> points;
  const _SpiralPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFDDE7EC)..style = PaintingStyle.stroke..strokeWidth = 2;
    final path = Path();
    for (int i = 0; i < 140; i++) {
      final angle = (i / 140) * 4 * 3.14159;
      final radius = 20 + (i / 140) * 90;
      final x = size.width / 2 + cos(angle) * radius;
      final y = size.height / 2 + sin(angle) * radius;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
    final active = Paint()..color = const Color(0xFF146C7A)..style = PaintingStyle.stroke..strokeWidth = 3;
    if (points.isNotEmpty) {
      final p = Path();
      p.moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        p.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(p, active);
    }
  }

  @override
  bool shouldRepaint(covariant _SpiralPainter oldDelegate) => oldDelegate.points != points;
}

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NeuroScan Behavioral Report')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFDDE7EC))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('LOW BEHAVIORAL DEVIATION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF2E8B57))),
              const SizedBox(height: 8),
              const Text('Your current assessment remains largely consistent with your behavioral baseline.', style: TextStyle(fontSize: 14, color: Color(0xFF62748B), height: 1.5)),
              const SizedBox(height: 12),
              const Text('87 / 100', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF0F2342))),
              const SizedBox(height: 8),
              const Text('Behavioral Stability Score', style: TextStyle(fontSize: 14, color: Color(0xFF62748B))),
            ])),
            const SizedBox(height: 16),
            const Text('Why did I receive this result?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F2342))),
            const SizedBox(height: 8),
            const Text('NeuroScan combines multiple behavioral signals rather than relying on a single assessment.', style: TextStyle(fontSize: 14, color: Color(0xFF62748B), height: 1.5)),
            const SizedBox(height: 12),
            const Text('NeuroScan AI is a research screening prototype and does not provide a medical diagnosis. Screening results should not replace evaluation by a qualified healthcare professional.', style: TextStyle(fontSize: 13, color: Color(0xFF62748B), height: 1.6)),
            const SizedBox(height: 16),
            const Row(children: [Expanded(child: _MetricTile(label: 'Cognitive', value: '35%')), Expanded(child: _MetricTile(label: 'Speech', value: '25%')),],),
            const SizedBox(height: 10),
            const Row(children: [Expanded(child: _MetricTile(label: 'Motor', value: '25%')), Expanded(child: _MetricTile(label: 'Interaction', value: '15%')),],),
          ]),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF0F8FA), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF62748B))),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F2342))),
      ]),
    );
  }
}

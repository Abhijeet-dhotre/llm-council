import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';
import 'blob_avatar.dart';

const _iosBlue = Color(0xFF007AFF);
const _bubbleGrey = Color(0xFFE9E9EB);

TextStyle _body(BuildContext context) =>
    GoogleFonts.plusJakartaSans(fontSize: 16, color: Colors.black87);

/// The user's own message — blue bubble on the right, iMessage style.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(left: 64, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: _iosBlue,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// An advisor's message — grey bubble on the left with its Bloub
/// blob and name above, like a group chat.
class AdvisorBubble extends StatelessWidget {
  const AdvisorBubble({
    super.key,
    required this.advisor,
    required this.text,
    this.mood = BlobMood.idle,
  });

  final Advisor advisor;
  final String text;
  final BlobMood mood;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 52, bottom: 3),
            child: Text(
              advisor.name,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BlobAvatar(advisor: advisor, mood: mood, size: 38),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    color: _bubbleGrey,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Text(text, style: _body(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Three dots while someone is thinking.
class TypingBubble extends StatefulWidget {
  const TypingBubble({
    super.key,
    required this.advisor,
    this.label,
  });

  final Advisor advisor;
  final String? label;

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 52, bottom: 3),
            child: Text(
              widget.label ?? widget.advisor.name,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BlobAvatar(
                advisor: widget.advisor,
                mood: BlobMood.thinking,
                size: 38,
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: const BoxDecoration(
                  color: _bubbleGrey,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, child) {
                    final v = _ctrl.value;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final phase = (v * 3 + i) % 3 / 3;
                        final y = -3 * (1 - (phase - 0.5).abs() * 2).clamp(
                          0.0,
                          1.0,
                        );
                        return Transform.translate(
                          offset: Offset(0, y),
                          child: Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: const BoxDecoration(
                              color: Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Chairman's verdict, as a chat message — not a card.
/// Green GO badge, confidence, and the first step up front.
class ChairmanBubble extends StatelessWidget {
  const ChairmanBubble({super.key, required this.verdict});

  final Verdict verdict;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 52, bottom: 3),
            child: Text(
              'Chairman',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ChairmanAvatar(size: 38),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: _bubbleGrey,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: verdict.decisionColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              verdict.decision.toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Confidence: ${verdict.confidence}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(verdict.why, style: _body(context)),
                      const SizedBox(height: 8),
                      _VerdictRow(
                        label: 'First step',
                        value: verdict.firstStep,
                      ),
                      _VerdictRow(
                        label: 'Biggest risk',
                        value: verdict.biggestRisk,
                      ),
                      _VerdictRow(
                        label: 'What would change this',
                        value: verdict.changesMind,
                      ),
                      if (verdict.dissent.isNotEmpty)
                        _VerdictRow(
                          label: 'Strongest objection',
                          value: verdict.dissent,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VerdictRow extends StatelessWidget {
  const _VerdictRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: Colors.black87,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

@immutable
class GameChatEntry {
  const GameChatEntry({
    required this.author,
    required this.message,
    required this.sentAt,
    required this.isMine,
  });

  final String author;
  final String message;
  final DateTime sentAt;
  final bool isMine;
}

class GameChatPanel extends StatelessWidget {
  const GameChatPanel({
    required this.entries,
    required this.inputController,
    required this.onSend,
    required this.title,
    this.helperText,
    super.key,
  });

  final List<GameChatEntry> entries;
  final TextEditingController inputController;
  final VoidCallback onSend;
  final String title;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x143FC1A7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Docked',
                    style: TextStyle(
                      color: Color(0xFF166555),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (helperText != null) ...[
              const SizedBox(height: 6),
              Text(
                helperText!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF57534E)),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x1A000000)),
                ),
                child: entries.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet',
                          style: TextStyle(color: Color(0xFF707070)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _ChatBubble(entry: entry);
                        },
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputController,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      isDense: true,
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: onSend, child: const Text('Send')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.entry});

  final GameChatEntry entry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: entry.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: entry.isMine
                ? const Color(0xFFDBFFF6)
                : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x18000000)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Column(
                crossAxisAlignment: entry.isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.author,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF5D5D5D),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1D1D1D),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

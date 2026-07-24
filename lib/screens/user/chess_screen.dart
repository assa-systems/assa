import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ════════════════════════════════════════════════════════════════════
// CHESS SCREEN — local 2-player, same-device
//
// NOTE: this is a simplified chess implementation:
//   • Standard piece movement + capture rules ARE enforced
//   • Check / checkmate / stalemate are NOT enforced (a king can be left
//     in check — game ends only when a king is actually captured)
//   • No castling, no en-passant, no under-promotion (pawns auto-promote
//     to Queen on reaching the last rank)
// This keeps the game fully playable while staying in scope for a
// same-device casual match. Can be hardened later with full rules.
//
// Board coordinates: row 0 = top (black back rank), row 7 = bottom
// (white back rank). White moves "up" (decreasing row).
// ════════════════════════════════════════════════════════════════════

class ChessScreen extends StatefulWidget {
  const ChessScreen({super.key});
  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  String _userName = '';

  // board[row][col] = '' or 'wP','wR','wN','wB','wQ','wK','bP', etc.
  late List<List<String>> _board;
  bool _whiteTurn = true;
  int? _selRow, _selCol;
  List<List<int>> _validMoves = [];
  bool _gameOver = false;
  String? _winnerLabel;
  bool _vsAi = true;
  bool _aiThinking = false;

  static String get _weekKey {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final week = ((monday.difference(DateTime(monday.year, 1, 1)).inDays +
        DateTime(monday.year, 1, 1).weekday -
        1) ~/
        7) +
        1;
    return '${monday.year}-W$week';
  }

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _resetBoard();
  }

  Future<void> _loadUserName() async {
    if (_uid.isEmpty) return;
    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      if (mounted) setState(() => _userName = doc.data()?['name'] ?? 'User');
    } catch (_) {}
  }

  void _resetBoard() {
    final b = List.generate(8, (_) => List.filled(8, ''));
    const backRank = ['R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R'];
    for (int c = 0; c < 8; c++) {
      b[0][c] = 'b${backRank[c]}';
      b[1][c] = 'bP';
      b[6][c] = 'wP';
      b[7][c] = 'w${backRank[c]}';
    }
    setState(() {
      _board = b;
      _whiteTurn = true;
      _selRow = null;
      _selCol = null;
      _validMoves = [];
      _gameOver = false;
      _winnerLabel = null;
    });
  }

  bool _inBounds(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  String _colorOf(String piece) => piece.isEmpty ? '' : piece[0];
  String _typeOf(String piece) => piece.isEmpty ? '' : piece[1];

  // ── Move generation (ignores check — simplified ruleset) ───────────
  List<List<int>> _movesFor(int r, int c) {
    final piece = _board[r][c];
    if (piece.isEmpty) return [];
    final color = _colorOf(piece);
    final type = _typeOf(piece);
    final moves = <List<int>>[];

    void tryAdd(int nr, int nc, {bool captureOnly = false, bool moveOnly = false}) {
      if (!_inBounds(nr, nc)) return;
      final target = _board[nr][nc];
      if (target.isEmpty) {
        if (!captureOnly) moves.add([nr, nc]);
      } else if (_colorOf(target) != color) {
        if (!moveOnly) moves.add([nr, nc]);
      }
    }

    void slide(List<List<int>> dirs) {
      for (final d in dirs) {
        int nr = r + d[0], nc = c + d[1];
        while (_inBounds(nr, nc)) {
          final target = _board[nr][nc];
          if (target.isEmpty) {
            moves.add([nr, nc]);
          } else {
            if (_colorOf(target) != color) moves.add([nr, nc]);
            break;
          }
          nr += d[0];
          nc += d[1];
        }
      }
    }

    switch (type) {
      case 'P':
        final dir = color == 'w' ? -1 : 1;
        final startRow = color == 'w' ? 6 : 1;
        // forward (no capture)
        if (_inBounds(r + dir, c) && _board[r + dir][c].isEmpty) {
          moves.add([r + dir, c]);
          if (r == startRow &&
              _inBounds(r + 2 * dir, c) &&
              _board[r + 2 * dir][c].isEmpty) {
            moves.add([r + 2 * dir, c]);
          }
        }
        // diagonal captures
        for (final dc in [-1, 1]) {
          final nr = r + dir, nc = c + dc;
          if (_inBounds(nr, nc) &&
              _board[nr][nc].isNotEmpty &&
              _colorOf(_board[nr][nc]) != color) {
            moves.add([nr, nc]);
          }
        }
        break;
      case 'N':
        const deltas = [
          [-2, -1], [-2, 1], [-1, -2], [-1, 2],
          [1, -2], [1, 2], [2, -1], [2, 1],
        ];
        for (final d in deltas) {
          tryAdd(r + d[0], c + d[1]);
        }
        break;
      case 'B':
        slide([[-1, -1], [-1, 1], [1, -1], [1, 1]]);
        break;
      case 'R':
        slide([[-1, 0], [1, 0], [0, -1], [0, 1]]);
        break;
      case 'Q':
        slide([
          [-1, -1], [-1, 1], [1, -1], [1, 1],
          [-1, 0], [1, 0], [0, -1], [0, 1],
        ]);
        break;
      case 'K':
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            tryAdd(r + dr, c + dc);
          }
        }
        break;
    }
    return moves;
  }

  void _onSquareTap(int r, int c) {
    if (_gameOver) return;
    final piece = _board[r][c];

    // Selecting own piece
    if (_selRow == null) {
      if (piece.isNotEmpty && _colorOf(piece) == (_whiteTurn ? 'w' : 'b')) {
        setState(() {
          _selRow = r;
          _selCol = c;
          _validMoves = _movesFor(r, c);
        });
      }
      return;
    }

    // Re-selecting another own piece
    if (piece.isNotEmpty && _colorOf(piece) == (_whiteTurn ? 'w' : 'b')) {
      setState(() {
        _selRow = r;
        _selCol = c;
        _validMoves = _movesFor(r, c);
      });
      return;
    }

    // Attempting a move
    final isValid = _validMoves.any((m) => m[0] == r && m[1] == c);
    if (!isValid) {
      setState(() {
        _selRow = null;
        _selCol = null;
        _validMoves = [];
      });
      return;
    }

    _makeMove(_selRow!, _selCol!, r, c);
  }

  void _makeMove(int fr, int fc, int tr, int tc) {
    final movingPiece = _board[fr][fc];
    final captured = _board[tr][tc];

    setState(() {
      _board[tr][tc] = movingPiece;
      _board[fr][fc] = '';

      // Auto-promote pawns reaching the last rank
      if (_typeOf(movingPiece) == 'P' && (tr == 0 || tr == 7)) {
        _board[tr][tc] = '${_colorOf(movingPiece)}Q';
      }

      _selRow = null;
      _selCol = null;
      _validMoves = [];

      if (_typeOf(captured) == 'K') {
        _gameOver = true;
        _winnerLabel = _whiteTurn ? 'White' : 'Black';
        _recordWin();
      } else {
        _whiteTurn = !_whiteTurn;
      }
    });

    if (!_whiteTurn && _vsAi && !_gameOver) {
      _triggerAiMove();
    }
  }

  void _triggerAiMove() {
    if (_aiThinking || _gameOver || _whiteTurn) return;
    setState(() => _aiThinking = true);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || _gameOver || _whiteTurn) return;

      // Find all valid moves for Black
      final blackMoves = <Map<String, dynamic>>[];
      for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
          if (_colorOf(_board[r][c]) == 'b') {
            final valid = _movesFor(r, c);
            for (final m in valid) {
              final targetPiece = _board[m[0]][m[1]];
              int weight = 0;
              if (targetPiece.isNotEmpty) {
                switch (_typeOf(targetPiece)) {
                  case 'K': weight = 1000; break;
                  case 'Q': weight = 90; break;
                  case 'R': weight = 50; break;
                  case 'B': case 'N': weight = 30; break;
                  case 'P': weight = 10; break;
                }
              }
              blackMoves.add({'from': [r, c], 'to': m, 'weight': weight});
            }
          }
        }
      }

      if (blackMoves.isEmpty) {
        setState(() {
          _aiThinking = false;
          _gameOver = true;
          _winnerLabel = 'White (Checkmate/No moves)';
        });
        return;
      }

      // Sort by capture value, then pick best
      blackMoves.sort((a, b) => (b['weight'] as int).compareTo(a['weight'] as int));
      final bestMove = blackMoves.first;
      final from = bestMove['from'] as List<int>;
      final to = bestMove['to'] as List<int>;

      setState(() => _aiThinking = false);
      _executeMove(from[0], from[1], to[0], to[1]);
    });
  }

  Future<void> _recordWin() async {
    if (_uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('game_scores').doc(_uid).set({
        'userId': _uid,
        'userName': _userName,
        'chess_weeklyPoints': FieldValue.increment(100),
        'chess_monthlyPoints': FieldValue.increment(100),
        'chess_weekKey': _weekKey,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  String _pieceEmoji(String piece) {
    if (piece.isEmpty) return '';
    final white = _colorOf(piece) == 'w';
    switch (_typeOf(piece)) {
      case 'K':
        return white ? '♔' : '♚';
      case 'Q':
        return white ? '♕' : '♛';
      case 'R':
        return white ? '♖' : '♜';
      case 'B':
        return white ? '♗' : '♝';
      case 'N':
        return white ? '♘' : '♞';
      case 'P':
        return white ? '♙' : '♟';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B1F27),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildTurnBanner(),
                      const SizedBox(height: 16),
                      _buildBoard(),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _resetBoard,
                            icon: const Icon(Icons.replay_rounded,
                                size: 16, color: Colors.white70),
                            label: const Text('New Game',
                                style: TextStyle(color: Colors.white70)),
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() => _vsAi = !_vsAi);
                              _resetBoard();
                            },
                            icon: Icon(_vsAi ? Icons.smart_toy_rounded : Icons.people_rounded, size: 16),
                            label: Text(_vsAi ? 'Mode: Vs AI' : 'Mode: 2 Players'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildHowToPlayBox(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHowToPlayBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_rounded, color: Color(0xFF64B5F6), size: 18),
              SizedBox(width: 8),
              Text('How to Play Chess',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 10),
          Text(
            '• Objective: Capture the opponent\'s King (♔ / ♚) to win the game.\n'
            '• Pawn (♙/♟): Moves forward 1 square (or 2 on initial move). Captures 1 square diagonally.\n'
            '• Knight (♘/♞): Moves in an "L-shape" (2 squares one way, 1 square perpendicular). Can jump over pieces.\n'
            '• Bishop (♗/♝): Moves diagonally any distance across open squares.\n'
            '• Rook (♖/♜): Moves horizontally or vertically any distance across open squares.\n'
            '• Queen (♕/♛): Combines Rook and Bishop moves (diagonals, rows, columns).\n'
            '• King (♔/♚): Moves 1 square in any direction.\n'
            '• Game Modes: Toggle between playing against AI Bot or same-device 2-player mode.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1B1F27),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2F3A))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chess',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                Text('Local 2-player · simplified rules',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnBanner() {
    if (_gameOver) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.4)),
        ),
        child: Text('🏆 $_winnerLabel wins!',
            style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 15,
                fontWeight: FontWeight.w800)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(_whiteTurn ? "White's Turn" : "Black's Turn",
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildBoard() {
    final screenW = MediaQuery.of(context).size.width - 32;
    final boardSize = screenW.clamp(0, 360).toDouble();
    final tile = boardSize / 8;

    return Container(
      width: boardSize,
      height: boardSize,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF3A3F4A), width: 3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: List.generate(8, (r) {
          return Expanded(
            child: Row(
              children: List.generate(8, (c) {
                final isDark = (r + c) % 2 == 1;
                final isSelected = _selRow == r && _selCol == c;
                final isValidMove =
                _validMoves.any((m) => m[0] == r && m[1] == c);
                final piece = _board[r][c];

                Color bg = isDark ? const Color(0xFF6B4226) : const Color(0xFFF0D9B5);
                if (isSelected) bg = const Color(0xFF64B5F6);

                return GestureDetector(
                  onTap: () => _onSquareTap(r, c),
                  child: Container(
                    width: tile,
                    height: tile,
                    color: bg,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (piece.isNotEmpty)
                          Text(_pieceEmoji(piece),
                              style: TextStyle(fontSize: tile * 0.62)),
                        if (isValidMove)
                          Container(
                            width: tile * 0.32,
                            height: tile * 0.32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: piece.isEmpty
                                  ? Colors.black.withOpacity(0.25)
                                  : Colors.transparent,
                              border: piece.isNotEmpty
                                  ? Border.all(
                                  color: Colors.redAccent.withOpacity(0.8),
                                  width: 2.5)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}
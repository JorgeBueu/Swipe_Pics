import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:intl/intl.dart';
import '../models/photo_item.dart';

class TrashScreen extends StatefulWidget {
  final List<PhotoItem> photosToDelete;

  const TrashScreen({super.key, required this.photosToDelete});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen>
    with SingleTickerProviderStateMixin {
  late List<PhotoItem> _items;
  bool _isDeleting = false;
  int _estimatedSizeBytes = 0;
  bool _sizeCalculated = false;
  String? _deleteError;
  bool _showToast = false;
  int _toastCount = 0;
  late AnimationController _toastAnimController;
  late Animation<double> _toastAnim;

  @override
  void initState() {
    super.initState();
    _toastAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _toastAnim = CurvedAnimation(
      parent: _toastAnimController,
      curve: Curves.easeOutCubic,
    );
    _items = List.from(widget.photosToDelete);
    _estimateTotalSize();
  }

  @override
  void dispose() {
    _toastAnimController.dispose();
    super.dispose();
  }

  void _estimateTotalSize() {
    int total = 0;
    for (final item in _items) {
      total += item.entity.width * item.entity.height * 3;
    }
    if (mounted) {
      setState(() {
        _estimatedSizeBytes = total;
        _sizeCalculated = true;
      });
    }
  }

  void _restore(PhotoItem item) {
    item.decision = Decision.pending;
    HapticFeedback.lightImpact();
    setState(() => _items.remove(item));
  }

  Future<void> _deleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('¿Eliminar definitivamente?'),
        content: Text(
          'Se eliminarán ${_items.length} foto${_items.length == 1 ? '' : 's'} '
          'de forma permanente.\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isDeleting = true;
      _deleteError = null;
    });

    bool allSucceeded = false;
    try {
      final ids = _items.map((e) => e.entity.id).toList();
      final result = await PhotoManager.editor.deleteWithIds(ids);
      allSucceeded = result != null;
    } catch (_) {
      allSucceeded = false;
    }

    if (!mounted) return;

    if (allSucceeded) {
      setState(() {
        _isDeleting = false;
        _showToast = true;
        _toastCount = _items.length;
      });
      _toastAnimController.forward();
      await Future.delayed(const Duration(seconds: 1, milliseconds: 500));
      if (mounted) {
        await _toastAnimController.reverse();
        if (mounted) Navigator.pop(context, true);
      }
    } else {
      setState(() {
        _isDeleting = false;
        _deleteError =
            'No se pudieron eliminar las fotos.\n'
            'Puede que no tengas permisos o que las fotos estén protegidas.';
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Revisar (${_items.length})'),
        actions: [
          if (_items.isNotEmpty && !_isDeleting)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _deleteAll,
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                icon: const Icon(Icons.delete_forever, size: 20),
                label: Text('Eliminar todo'),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isDeleting) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 24),
              const Text(
                'Eliminando fotos...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_showToast) {
      return _buildSuccessToast();
    }

    if (_deleteError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, size: 64, color: Colors.amber),
              const SizedBox(height: 16),
              Text(
                _deleteError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Volver'),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: _deleteAll,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.greenAccent),
            SizedBox(height: 16),
            Text('No hay fotos para eliminar',
                style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildStatsBar(),
        Expanded(child: _buildGrid()),
      ],
    );
  }

  Widget _buildSuccessToast() {
    return Stack(
      children: [
        Container(color: Colors.black.withOpacity(0.3)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Align(
              alignment: Alignment.topCenter,
              child: FadeTransition(
                opacity: _toastAnim,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.green.shade700,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        '$_toastCount foto${_toastCount == 1 ? '' : 's'} '
                        'eliminada${_toastCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsBar() {
    final totalOriginal = widget.photosToDelete.length;
    final restored = totalOriginal - _items.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: const Color(0xFF1A1A2E),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MiniStat(
                      icon: Icons.delete,
                      label: '${_items.length}',
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 24),
                    _MiniStat(
                      icon: Icons.restore,
                      label: '$restored',
                      color: Colors.greenAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Row(
                    children: [
                      Expanded(
                        flex: _items.length > 0 ? _items.length : 1,
                        child: Container(
                          height: 6,
                          color: Colors.redAccent,
                        ),
                      ),
                      if (restored > 0)
                        Expanded(
                          flex: restored,
                          child: Container(
                            height: 6,
                            color: Colors.greenAccent.withOpacity(0.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (_sizeCalculated)
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: _estimatedSizeBytes),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => _MiniStat(
                icon: Icons.storage,
                label: _formatSize(v),
                color: Colors.amber,
              ),
            )
          else
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _items.length,
      itemBuilder: (_, index) => _buildGridItem(_items[index], index),
    );
  }

  Widget _buildGridItem(PhotoItem item, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 50).clamp(0, 500)),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: AssetEntityImageProvider(
                item.entity,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(300),
                thumbnailFormat: ThumbnailFormat.jpeg,
              ),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF1A1A2E),
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _restore(item),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: const Icon(Icons.restore, color: Colors.white, size: 16),
                ),
              ),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              right: 6,
              child: Text(
                DateFormat('d/M').format(item.entity.createDateTime),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

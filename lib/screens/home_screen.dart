import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:intl/intl.dart';
import '../models/photo_item.dart';
import 'trash_screen.dart';

enum SortOrder { dateDesc, dateAsc, random }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<PhotoItem> _photos = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  String? _error;
  SortOrder _sortOrder = SortOrder.dateDesc;
  String _loadProgress = '';
  final _cardController = SwipeableCardController();

  static const int _pageSize = 500;

  String get _sortLabel {
    switch (_sortOrder) {
      case SortOrder.dateDesc:
        return 'Más recientes';
      case SortOrder.dateAsc:
        return 'Más antiguas';
      case SortOrder.random:
        return 'Aleatorio';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPhotos());
  }

  Future<void> _loadPhotos() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _loadProgress = 'Solicitando permisos...';
    });

    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!mounted) return;

      if (!perm.isAuth) {
        setState(() {
          _error = 'perm_denied';
          _isLoading = false;
        });
        return;
      }

      _loadProgress = 'Leyendo galería...';
      setState(() {});

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
      );
      if (!mounted) return;

      if (albums.isEmpty) {
        setState(() {
          _photos = [];
          _isLoading = false;
        });
        return;
      }

      final allAlbum = albums.first;
      final totalCount = await allAlbum.assetCountAsync;
      if (!mounted) return;

      if (totalCount == 0) {
        setState(() {
          _photos = [];
          _isLoading = false;
        });
        return;
      }

      final allPhotos = <AssetEntity>[];
      final limit = totalCount;
      int page = 0;

      while (allPhotos.length < limit) {
        final photos = await allAlbum.getAssetListPaged(
          page: page,
          size: _pageSize,
        );
        if (photos.isEmpty) break;

        allPhotos.addAll(photos);
        page++;

        if (mounted) {
          setState(() {
            _loadProgress = '${allPhotos.length} / $limit fotos';
          });
        }

        if (allPhotos.length < limit) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
        if (!mounted) return;
      }

      switch (_sortOrder) {
        case SortOrder.dateAsc:
          allPhotos.sort(
              (a, b) => a.createDateTime.compareTo(b.createDateTime));
          break;
        case SortOrder.dateDesc:
          allPhotos.sort(
              (a, b) => b.createDateTime.compareTo(a.createDateTime));
          break;
        case SortOrder.random:
          allPhotos.shuffle(Random());
          break;
      }

      if (!mounted) return;
      _photos = allPhotos.map((e) => PhotoItem(e)).toList();
      _currentIndex = 0;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al cargar fotos: $e';
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _changeSort(SortOrder order) {
    _sortOrder = order;
    setState(() {
      for (final p in _photos) {
        p.decision = Decision.pending;
      }
      switch (order) {
        case SortOrder.dateAsc:
          _photos.sort(
              (a, b) => a.entity.createDateTime.compareTo(b.entity.createDateTime));
          break;
        case SortOrder.dateDesc:
          _photos.sort(
              (a, b) => b.entity.createDateTime.compareTo(a.entity.createDateTime));
          break;
        case SortOrder.random:
          _photos.shuffle(Random(DateTime.now().microsecondsSinceEpoch));
          break;
      }
      _currentIndex = 0;
    });
  }

  void _onSwipedRight() {
    if (_currentIndex >= _photos.length) return;
    _photos[_currentIndex].decision = Decision.keep;
    setState(() => _currentIndex++);
  }

  void _onSwipedLeft() {
    if (_currentIndex >= _photos.length) return;
    _photos[_currentIndex].decision = Decision.delete;
    setState(() => _currentIndex++);
  }

  void _onButtonKeep() {
    HapticFeedback.heavyImpact();
    _cardController.flyRight?.call();
  }

  void _onButtonDelete() {
    HapticFeedback.heavyImpact();
    _cardController.flyLeft?.call();
  }

  Future<void> _openSettings() async {
    await PhotoManager.openSetting();
    _loadPhotos();
  }

  void _openTrash() async {
    final toDelete =
        _photos.where((p) => p.decision == Decision.delete).toList();
    if (toDelete.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay fotos marcadas para eliminar')),
      );
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => TrashScreen(photosToDelete: toDelete),
        transitionsBuilder: (_, a, __, child) =>
            SlideTransition(position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );

    if (result == true && mounted) {
      _photos.removeWhere((p) => p.decision == Decision.delete);
      if (_currentIndex >= _photos.length) {
        _currentIndex = _photos.length;
      }
      setState(() {});
    }
  }

  void _undoLast() {
    if (_currentIndex <= 0) return;
    _currentIndex--;
    _photos[_currentIndex].decision = Decision.pending;
    HapticFeedback.lightImpact();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF7C4DFF),
                ),
              ),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _loadProgress.isNotEmpty ? _loadProgress : 'Cargando fotos...',
                  key: ValueKey(_loadProgress),
                  style: const TextStyle(color: Colors.grey, fontSize: 15),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    backgroundColor: Color(0xFF1A1A2E),
                    color: Color(0xFF7C4DFF),
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error == 'perm_denied') {
      return _buildPermissionDenied();
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadPhotos,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_photos.isEmpty) {
      return _buildEmptyGallery();
    }

    if (_currentIndex >= _photos.length) {
      return _buildDoneScreen();
    }

    return _buildSwipingScreen();
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            const Text(
              'Permiso necesario',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Swipe Pics necesita acceso a tus fotos.\n\n'
              'Concede el permiso "Fotos y vídeos" en los ajustes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Abrir ajustes'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadPhotos,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyGallery() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No hay fotos en tu galería',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _loadPhotos,
              icon: const Icon(Icons.refresh),
              label: const Text('Volver a cargar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneScreen() {
    final kept = _photos.where((p) => p.decision == Decision.keep).length;
    final deleted = _photos.where((p) => p.decision == Decision.delete).length;
    final total = kept + deleted;
    final keptFraction = total > 0 ? kept / total : 0.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AnimatedCheck(),
            const SizedBox(height: 24),
            const Text(
              '¡Has terminado!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: keptFraction,
                    strokeWidth: 12,
                    backgroundColor: Colors.redAccent.withOpacity(0.15),
                    color: Colors.greenAccent,
                    strokeCap: StrokeCap.round,
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 28),
                        const SizedBox(height: 4),
                        TweenAnimationBuilder<int>(
                          tween: IntTween(begin: 0, end: kept),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => Text(
                            '$v',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ),
                        const Text('conservadas', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '$deleted foto${deleted == 1 ? '' : 's'} para eliminar',
              style: TextStyle(
                fontSize: 16,
                color: Colors.redAccent.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (deleted > 0)
                  FilledButton.icon(
                    onPressed: _openTrash,
                    icon: const Icon(Icons.delete_sweep),
                    label: Text('Revisar $deleted fotos'),
                  ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: () {
                    _currentIndex = 0;
                    for (final p in _photos) {
                      p.decision = Decision.pending;
                    }
                    setState(() {});
                  },
                  child: const Text('Empezar de nuevo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipingScreen() {
    final photo = _photos[_currentIndex];
    final total = _photos.length;
    final done = _currentIndex;
    final progress = total > 0 ? done / total : 0.0;

    return Column(
      children: [
        _buildTopBar(total, done, progress),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SwipeableCard(
              key: ValueKey(photo.entity.id),
              controller: _cardController,
              onKeep: _onSwipedRight,
              onDelete: _onSwipedLeft,
              child: _buildPhotoCard(photo),
            ),
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildTopBar(int total, int done, double progress) {
    final toDelete =
        _photos.where((p) => p.decision == Decision.delete).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _sortLabel,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              PopupMenuButton<SortOrder>(
                icon: const Icon(Icons.sort, size: 20),
                onSelected: _changeSort,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: SortOrder.dateDesc, child: Text('Más recientes')),
                  const PopupMenuItem(
                      value: SortOrder.dateAsc, child: Text('Más antiguas')),
                  const PopupMenuItem(
                      value: SortOrder.random, child: Text('Aleatorio')),
                ],
              ),
              if (toDelete > 0) ...[
                const SizedBox(width: 2),
                Badge(
                  isLabelVisible: toDelete > 0,
                  label: Text('$toDelete',
                      style: const TextStyle(fontSize: 9)),
                  child: IconButton(
                    icon: const Icon(Icons.delete_sweep, size: 20),
                    onPressed: _openTrash,
                    tooltip: 'Papelera',
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
              const SizedBox(width: 2),
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: done > 0 ? done - 1 : 0, end: done),
                duration: const Duration(milliseconds: 200),
                builder: (_, count, __) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count/$total',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: const Color(0xFF1A1A2E),
              color: const Color(0xFF7C4DFF),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoCard(PhotoItem photo) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF0D0D0D),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: AssetEntityImageProvider(
                photo.entity,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(1000),
                thumbnailFormat: ThumbnailFormat.jpeg,
              ),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF1A1A2E),
                child: const Center(
                  child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.5),
                      Colors.black.withOpacity(0.9),
                      Colors.black,
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('d MMM yyyy, HH:mm')
                          .format(photo.entity.createDateTime),
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      photo.entity.title ?? 'Sin nombre',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final toDelete =
        _photos.where((p) => p.decision == Decision.delete).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ActionButton(
                icon: Icons.close_rounded,
                color: Colors.redAccent,
                onPressed: _onButtonDelete,
                size: 64,
              ),
              if (_currentIndex > 0)
                _ActionButton(
                  icon: Icons.undo_rounded,
                  color: Colors.amber,
                  onPressed: _undoLast,
                  size: 52,
                ),
              _ActionButton(
                icon: Icons.favorite_rounded,
                color: Colors.greenAccent,
                onPressed: _onButtonKeep,
                size: 64,
              ),
            ],
          ),
          if (toDelete > 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openTrash,
                icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                label: Text(
                  'Papelera  ·  $toDelete foto${toDelete == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent.withOpacity(0.85),
                  side: BorderSide(
                    color: Colors.redAccent.withOpacity(0.25),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnimatedCheck extends StatefulWidget {
  const _AnimatedCheck();

  @override
  State<_AnimatedCheck> createState() => _AnimatedCheckState();
}

class _AnimatedCheckState extends State<_AnimatedCheck>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: const Icon(Icons.check_circle, size: 80, color: Colors.greenAccent),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final double size;

  const _ActionButton({
    required this.icon,
    required this.color,
    this.onPressed,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: color.withOpacity(0.12),
        foregroundColor: color,
        iconSize: size * 0.45,
        minimumSize: Size(size, size),
        maximumSize: Size(size, size),
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: color.withOpacity(0.4),
      ),
      onPressed: onPressed,
    );
  }
}

class SwipeableCardController {
  void Function()? flyLeft;
  void Function()? flyRight;
}

class SwipeableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onKeep;
  final VoidCallback onDelete;
  final SwipeableCardController? controller;

  const SwipeableCard({
    super.key,
    required this.child,
    required this.onKeep,
    required this.onDelete,
    this.controller,
  });

  @override
  State<SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<SwipeableCard>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late AnimationController _entranceController;
  late Animation<Offset> _dragAnim;
  CurvedAnimation? _dragCurve;
  Offset _dragOffset = Offset.zero;
  bool _isAnimating = false;
  bool _hapticAtThreshold = false;

  static const double _threshold = 120;
  static const double _maxRotateRad = 0.4;

  @override
  void initState() {
    super.initState();

    widget.controller?.flyLeft = _animateFlyLeft;
    widget.controller?.flyRight = _animateFlyRight;

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _entranceController.forward();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _dragAnim = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(_animController);
    _animController.addListener(() {
      setState(() => _dragOffset = _dragAnim.value);
    });
    _animController.addStatusListener((s) {
      if (s == AnimationStatus.completed && _isAnimating) {
        _isAnimating = false;
        if (_dragOffset.dx.abs() > 400) {
          if (_dragOffset.dx > 0) widget.onKeep();
          else widget.onDelete();
        }
        _dragOffset = Offset.zero;
      }
    });
  }

  @override
  void dispose() {
    _dragCurve?.dispose();
    _animController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _startAnim(Offset from, Offset to, Curve curve, {int ms = 400}) {
    _isAnimating = true;
    _dragCurve?.dispose();
    _dragCurve = CurvedAnimation(parent: _animController, curve: curve);
    _dragAnim = Tween<Offset>(begin: from, end: to).animate(_dragCurve!);
    _animController.reset();
    _animController.duration = Duration(milliseconds: ms);
    _animController.forward();
  }

  void _animateFlyLeft() {
    if (_isAnimating) return;
    _startAnim(Offset.zero, const Offset(-500, 0), Curves.easeInCubic, ms: 300);
  }

  void _animateFlyRight() {
    if (_isAnimating) return;
    _startAnim(Offset.zero, const Offset(500, 0), Curves.easeInCubic, ms: 300);
  }

  void _onPanStart(DragStartDetails _) {
    if (_isAnimating) return;
    _hapticAtThreshold = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_isAnimating) return;
    setState(() => _dragOffset += d.delta);

    if (_dragOffset.dx.abs() > _threshold && !_hapticAtThreshold) {
      _hapticAtThreshold = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onPanEnd(DragEndDetails _) {
    if (_isAnimating) return;

    if (_dragOffset.dx.abs() > _threshold) {
      HapticFeedback.heavyImpact();
      final sign = _dragOffset.dx > 0 ? 1.0 : -1.0;
      _startAnim(
        _dragOffset,
        Offset(sign * 500, _dragOffset.dy * 0.3),
        Curves.easeInCubic,
        ms: 300,
      );
    } else {
      _startAnim(_dragOffset, Offset.zero, Curves.easeOutBack, ms: 500);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dx = _dragOffset.dx;
    final rotation = (dx / 400).clamp(-_maxRotateRad, _maxRotateRad);
    final opacity = (dx.abs() / _threshold).clamp(0.0, 1.0);

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: AnimatedBuilder(
        animation: _entranceController,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_entranceController.value);
          return Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
          );
        },
        child: Transform(
          transform: Matrix4.identity()
            ..translate(_dragOffset.dx, _dragOffset.dy)
            ..rotateZ(rotation),
          alignment: Alignment.center,
          child: Stack(
            children: [
              widget.child,
              if (dx > 5)
                Positioned(
                  top: 32, left: 24,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.rotate(
                      angle: -0.15,
                      child: _SwipeBadge(text: 'CONSERVAR', color: Colors.greenAccent),
                    ),
                  ),
                ),
              if (dx < -5)
                Positioned(
                  top: 32, right: 24,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.rotate(
                      angle: 0.15,
                      child: _SwipeBadge(text: 'BORRAR', color: Colors.redAccent),
                    ),
                  ),
                ),
              if (dx > _threshold * 0.5)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.greenAccent.withOpacity(opacity * 0.6), width: 4),
                    ),
                  ),
                ),
              if (dx < -_threshold * 0.5)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.redAccent.withOpacity(opacity * 0.6), width: 4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _SwipeBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(10),
        color: color.withOpacity(0.1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

import 'dart:js_interop';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'package:web/web.dart' as web;
import '../app.dart';
import '../core/providers/environment_provider.dart';

class NewsPostItem {
  final String id;
  final String title;
  final String content;
  final String imageUrl;
  final String category; // 'promo' | 'news' | 'advertisement' | 'announcement'
  final String? promoCode;
  final String actionType; // 'link' | 'promo' | 'none'
  final String? actionUrl;
  final bool isActive;
  final DateTime createdAt;
  final String? buttonText;
  final double? buttonX;
  final double? buttonY;
  final double? buttonWidth;
  final double? buttonHeight;
  final String? buttonLink;
  final String? buttonBgColor;
  final String? buttonTextColor;
  final String? buttonBorderColor;
  final double? buttonBorderWidth;
  final double? buttonBorderRadius;
  final double? buttonPaddingV;
  final double? buttonPaddingH;

  NewsPostItem({
    required this.id,
    required this.title,
    required this.content,
    required this.imageUrl,
    required this.category,
    this.promoCode,
    required this.actionType,
    this.actionUrl,
    required this.isActive,
    required this.createdAt,
    this.buttonText,
    this.buttonX,
    this.buttonY,
    this.buttonWidth,
    this.buttonHeight,
    this.buttonLink,
    this.buttonBgColor,
    this.buttonTextColor,
    this.buttonBorderColor,
    this.buttonBorderWidth,
    this.buttonBorderRadius,
    this.buttonPaddingV,
    this.buttonPaddingH,
  });

  factory NewsPostItem.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return NewsPostItem(
      id: id,
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      category: map['category'] ?? 'news',
      promoCode: map['promoCode'],
      actionType: map['actionType'] ?? 'none',
      actionUrl: map['actionUrl'],
      isActive: map['isActive'] != false,
      createdAt: parseDate(map['createdAt']),
      buttonText: map['buttonText'],
      buttonX: (map['buttonX'] as num?)?.toDouble(),
      buttonY: (map['buttonY'] as num?)?.toDouble(),
      buttonWidth: (map['buttonWidth'] as num?)?.toDouble(),
      buttonHeight: (map['buttonHeight'] as num?)?.toDouble(),
      buttonLink: map['buttonLink'],
      buttonBgColor: map['buttonBgColor'],
      buttonTextColor: map['buttonTextColor'],
      buttonBorderColor: map['buttonBorderColor'],
      buttonBorderWidth: (map['buttonBorderWidth'] as num?)?.toDouble(),
      buttonBorderRadius: (map['buttonBorderRadius'] as num?)?.toDouble(),
      buttonPaddingV: (map['buttonPaddingV'] as num?)?.toDouble(),
      buttonPaddingH: (map['buttonPaddingH'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'imageUrl': imageUrl,
      'category': category,
      'promoCode': promoCode,
      'actionType': actionType,
      'actionUrl': actionUrl,
      'isActive': isActive,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'buttonText': buttonText,
      'buttonX': buttonX,
      'buttonY': buttonY,
      'buttonWidth': buttonWidth,
      'buttonHeight': buttonHeight,
      'buttonLink': buttonLink,
      'buttonBgColor': buttonBgColor,
      'buttonTextColor': buttonTextColor,
      'buttonBorderColor': buttonBorderColor,
      'buttonBorderWidth': buttonBorderWidth,
      'buttonBorderRadius': buttonBorderRadius,
      'buttonPaddingV': buttonPaddingV,
      'buttonPaddingH': buttonPaddingH,
    };
  }
}

final newsPostsStreamProvider = StreamProvider<List<NewsPostItem>>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final userAsync = ref.watch(activeEnvAuthUserProvider);

  if (userAsync.value == null) {
    return Stream.value(<NewsPostItem>[]);
  }

  return firestore
      .collection('news_posts')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) {
        return snap.docs.map((doc) => NewsPostItem.fromMap(doc.id, doc.data())).toList();
      })
      .handleError((err) {
        print('[NewsConsole] Stream failed: $err');
        return <NewsPostItem>[];
      });
});

class NewsPage extends StatefulComponent {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  int _formVersion = 0;

  // Editor states
  String _editingId = '';
  String _title = '';
  String _content = '';
  String _imageUrl = '';
  String _category = 'news';
  String _promoCode = '';
  String _actionType = 'none';
  String _actionUrl = '';
  bool _isActive = true;

  // Custom button configurations
  String _buttonText = '';
  String _buttonXStr = '10';
  String _buttonYStr = '80';
  String _buttonWidthStr = '30';
  String _buttonHeightStr = '12';
  String _buttonBgColor = '#4f46e5';
  String _buttonTextColor = '#ffffff';
  String _buttonBorderColor = '#4f46e5';
  String _buttonBorderWidth = '1';
  String _buttonBorderRadius = '8';
  String _buttonPaddingV = '8';
  String _buttonPaddingH = '16';

  bool _isSaving = false;

  void _resetForm() {
    setState(() {
      _editingId = '';
      _title = '';
      _content = '';
      _imageUrl = '';
      _category = 'news';
      _promoCode = '';
      _actionType = 'none';
      _actionUrl = '';
      _isActive = true;
      _buttonText = '';
      _buttonXStr = '10';
      _buttonYStr = '80';
      _buttonWidthStr = '30';
      _buttonHeightStr = '12';
      _buttonBgColor = '#4f46e5';
      _buttonTextColor = '#ffffff';
      _buttonBorderColor = '#4f46e5';
      _buttonBorderWidth = '1';
      _buttonBorderRadius = '8';
      _buttonPaddingV = '8';
      _buttonPaddingH = '16';
      _formVersion++;
    });
  }

  void _selectPost(NewsPostItem item) {
    setState(() {
      _editingId = item.id;
      _title = item.title;
      _content = item.content;
      _imageUrl = item.imageUrl;
      _category = item.category;
      _promoCode = item.promoCode ?? '';
      _actionType = item.actionType;
      _actionUrl = item.actionUrl ?? '';
      _isActive = item.isActive;
      _buttonText = item.buttonText ?? '';
      _buttonXStr = item.buttonX?.toStringAsFixed(0) ?? '10';
      _buttonYStr = item.buttonY?.toStringAsFixed(0) ?? '80';
      _buttonWidthStr = item.buttonWidth?.toStringAsFixed(0) ?? '30';
      _buttonHeightStr = item.buttonHeight?.toStringAsFixed(0) ?? '12';
      _buttonBgColor = item.buttonBgColor ?? '#4f46e5';
      _buttonTextColor = item.buttonTextColor ?? '#ffffff';
      _buttonBorderColor = item.buttonBorderColor ?? '#4f46e5';
      _buttonBorderWidth = item.buttonBorderWidth?.toStringAsFixed(0) ?? '1';
      _buttonBorderRadius = item.buttonBorderRadius?.toStringAsFixed(0) ?? '8';
      _buttonPaddingV = item.buttonPaddingV?.toStringAsFixed(0) ?? '8';
      _buttonPaddingH = item.buttonPaddingH?.toStringAsFixed(0) ?? '16';
      _formVersion++;
    });
  }

  void _handleImageUpload(web.Event event) {
    final input = event.target as web.HTMLInputElement;
    final files = input.files;
    if (files == null || files.length == 0) return;
    final file = files.item(0)!;

    final reader = web.FileReader();
    reader.readAsDataURL(file);
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result != null) {
        final img = web.HTMLImageElement();
        img.src = result.toString();
        img.onLoad.listen((_) {
          final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
          final maxW = 800;
          var w = img.naturalWidth;
          var h = img.naturalHeight;
          if (w > maxW) {
            h = (h * (maxW / w)).round();
            w = maxW;
          }
          canvas.width = w;
          canvas.height = h;
          final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
          ctx.drawImage(img, 0, 0, w, h);
          final compressedDataUrl = canvas.toDataURL('image/jpeg', 0.75 as JSAny?);
          setState(() {
            _imageUrl = compressedDataUrl;
            _formVersion++;
          });
        });
      }
    });
  }

  void _savePost() async {
    if (_title.trim().isEmpty || _content.trim().isEmpty) {
      web.window.alert('Title and Content are required.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final firestore = context.read(firestoreProvider);
      final data = {
        'title': _title.trim(),
        'content': _content.trim(),
        'imageUrl': _imageUrl.trim(),
        'category': _category,
        'promoCode': _promoCode.trim().isNotEmpty ? _promoCode.trim().toUpperCase() : null,
        'actionType': _actionType,
        'actionUrl': _actionUrl.trim().isNotEmpty ? _actionUrl.trim() : null,
        'isActive': _isActive,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'buttonText': _buttonText.trim().isNotEmpty ? _buttonText.trim() : null,
        'buttonX': double.tryParse(_buttonXStr),
        'buttonY': double.tryParse(_buttonYStr),
        'buttonWidth': double.tryParse(_buttonWidthStr),
        'buttonHeight': double.tryParse(_buttonHeightStr),
        'buttonBgColor': _buttonBgColor.trim().isNotEmpty ? _buttonBgColor.trim() : null,
        'buttonTextColor': _buttonTextColor.trim().isNotEmpty ? _buttonTextColor.trim() : null,
        'buttonBorderColor': _buttonBorderColor.trim().isNotEmpty ? _buttonBorderColor.trim() : null,
        'buttonBorderWidth': double.tryParse(_buttonBorderWidth),
        'buttonBorderRadius': double.tryParse(_buttonBorderRadius),
        'buttonPaddingV': double.tryParse(_buttonPaddingV),
        'buttonPaddingH': double.tryParse(_buttonPaddingH),
      };

      if (_editingId.isNotEmpty) {
        await firestore.collection('news_posts').doc(_editingId).update(data);
      } else {
        await firestore.collection('news_posts').add(data);
      }

      _resetForm();
    } catch (e) {
      web.window.alert('Failed to save post: $e');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _deletePost(String id) async {
    if (!web.window.confirm('Are you sure you want to delete this post?')) return;
    try {
      final firestore = context.read(firestoreProvider);
      await firestore.collection('news_posts').doc(id).delete();
      if (_editingId == id) _resetForm();
    } catch (e) {
      web.window.alert('Failed to delete post: $e');
    }
  }

  @override
  Component build(BuildContext context) {
    final postsAsync = context.watch(newsPostsStreamProvider);

    final double? bX = double.tryParse(_buttonXStr);
    final double? bY = double.tryParse(_buttonYStr);
    final double? bW = double.tryParse(_buttonWidthStr);
    final double? bH = double.tryParse(_buttonHeightStr);

    return div(classes: 'p-6 space-y-8 flex flex-col', [
      // Title Bar
      div(classes: 'flex justify-between items-center', [
        div([
          h1(classes: 'text-2xl font-black text-zinc-900 uppercase tracking-wider', [
            Component.text('News & Promotional Banners'),
          ]),
          p(classes: 'text-xs text-zinc-500 font-semibold', [
            Component.text('Configure banners, custom buttons, links, and promo codes for mobile & web apps.'),
          ]),
        ]),
      ]),

      // Two Column Layout: Editor + Previews / Table
      div(classes: 'grid grid-cols-1 lg:grid-cols-12 gap-8 items-start', [
        // Left side: Editor & Previews
        div(classes: 'lg:col-span-8 space-y-8', [
          // Previews panel (Side-by-side)
          div(classes: 'bg-white rounded-3xl border border-zinc-200/60 p-6 space-y-6 shadow-sm', [
            div(classes: 'flex justify-between items-center border-b border-zinc-100 pb-3', [
              h2(classes: 'text-sm font-bold text-zinc-800 uppercase tracking-wider', [
                Component.text('Live Position Previews'),
              ]),
              span(classes: 'px-2.5 py-1 text-[10px] bg-indigo-50 text-indigo-500 rounded-lg font-bold', [
                Component.text('X, Y Coordinates Overlay'),
              ]),
            ]),

            div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-6', [
              // Web layout card preview
              div(classes: 'space-y-3', [
                p(classes: 'text-xs font-bold text-zinc-500 uppercase tracking-wider text-center', [
                  Component.text('💻 Web View Preview'),
                ]),
                div(
                  classes:
                      'rounded-2xl border border-zinc-200 overflow-hidden bg-zinc-950 relative aspect-video flex items-center justify-center text-zinc-400',
                  [
                    if (_imageUrl.trim().isNotEmpty)
                      img(src: _imageUrl.trim(), classes: 'w-full h-full object-cover')
                    else
                      Component.text('No Banner Image Uploaded'),

                    // Web Button Overlay
                    if (_buttonText.trim().isNotEmpty && bX != null && bY != null && bW != null && bH != null)
                      button(
                        classes:
                            'absolute text-center flex items-center justify-center shadow-lg text-[10px] md:text-xs pointer-events-none',
                        attributes: {
                          'style':
                              'left: $bX%; top: $bY%; width: $bW%; height: $bH%; box-sizing: border-box; '
                              'background-color: $_buttonBgColor; color: $_buttonTextColor; '
                              'border: ${_buttonBorderWidth}px solid $_buttonBorderColor; '
                              'border-radius: ${_buttonBorderRadius}px; '
                              'padding: ${_buttonPaddingV}px ${_buttonPaddingH}px;',
                        },
                        [Component.text(_buttonText)],
                      ),
                  ],
                ),
              ]),

              // Mobile layout card preview
              div(classes: 'space-y-3', [
                p(classes: 'text-xs font-bold text-zinc-500 uppercase tracking-wider text-center', [
                  Component.text('📱 Mobile View Preview'),
                ]),
                div(classes: 'flex justify-center', [
                  // Smartphone wrapper mockup frame
                  div(
                    classes:
                        'w-64 border-[6px] border-zinc-800 rounded-[32px] overflow-hidden bg-zinc-900 shadow-xl relative aspect-[9/16] flex flex-col justify-end p-2',
                    [
                      // Image banner container inside card
                      div(
                        classes:
                            'w-full aspect-video rounded-xl border border-zinc-800 overflow-hidden bg-zinc-950 relative flex items-center justify-center text-zinc-400',
                        [
                          if (_imageUrl.trim().isNotEmpty)
                            img(src: _imageUrl.trim(), classes: 'w-full h-full object-cover')
                          else
                            Component.text('No Image'),

                          // Mobile Button Overlay
                          if (_buttonText.trim().isNotEmpty && bX != null && bY != null && bW != null && bH != null)
                            button(
                              classes:
                                  'absolute text-center flex items-center justify-center shadow-md text-[8px] pointer-events-none',
                              attributes: {
                                'style':
                                    'left: $bX%; top: $bY%; width: $bW%; height: $bH%; box-sizing: border-box; '
                                    'background-color: $_buttonBgColor; color: $_buttonTextColor; '
                                    'border: ${(double.tryParse(_buttonBorderWidth) ?? 1) * 0.6}px solid $_buttonBorderColor; '
                                    'border-radius: ${(double.tryParse(_buttonBorderRadius) ?? 8) * 0.6}px; '
                                    'padding: ${(double.tryParse(_buttonPaddingV) ?? 8) * 0.6}px ${(double.tryParse(_buttonPaddingH) ?? 16) * 0.6}px;',
                              },
                              [Component.text(_buttonText)],
                            ),
                        ],
                      ),
                      // Mimic mobile card details below image
                      div(classes: 'bg-zinc-800 p-2.5 rounded-xl mt-2 space-y-1', [
                        div(classes: 'flex justify-between items-center', [
                          span(classes: 'px-2 py-0.5 rounded text-[8px] font-bold bg-green-500/10 text-green-400', [
                            Component.text(_category.toUpperCase()),
                          ]),
                          span(classes: 'text-[8px] text-zinc-500', [Component.text('Today')]),
                        ]),
                        p(classes: 'text-[10px] font-bold text-zinc-200 truncate', [
                          Component.text(_title.isEmpty ? 'Post Title' : _title),
                        ]),
                        p(classes: 'text-[8px] text-zinc-400 line-clamp-2 leading-relaxed', [
                          Component.text(_content.isEmpty ? 'Post description and content goes here...' : _content),
                        ]),
                      ]),
                    ],
                  ),
                ]),
              ]),
            ]),
          ]),

          // Table list of postings
          div(classes: 'bg-white rounded-3xl border border-zinc-200/60 overflow-hidden shadow-sm', [
            div(classes: 'px-6 py-4 border-b border-zinc-100 flex justify-between items-center', [
              h2(classes: 'text-sm font-bold text-zinc-800 uppercase tracking-wider', [
                Component.text('Active Banners & Postings'),
              ]),
            ]),

            postsAsync.when(
              data: (posts) {
                if (posts.isEmpty) {
                  return div(classes: 'p-12 text-center text-zinc-400 text-sm font-semibold', [
                    Component.text('No promotional banners found. Create one above!'),
                  ]);
                }

                return table(classes: 'w-full text-left border-collapse text-xs', [
                  thead(classes: 'bg-zinc-50 border-b border-zinc-150/40 text-zinc-500 font-extrabold uppercase', [
                    tr([
                      th(classes: 'px-6 py-3', [Component.text('Banner')]),
                      th(classes: 'px-6 py-3', [Component.text('Title')]),
                      th(classes: 'px-6 py-3', [Component.text('Category')]),
                      th(classes: 'px-6 py-3', [Component.text('Action Type')]),
                      th(classes: 'px-6 py-3', [Component.text('Status')]),
                      th(classes: 'px-6 py-3 text-right', [Component.text('Actions')]),
                    ]),
                  ]),
                  tbody(classes: 'divide-y divide-zinc-100 font-medium text-zinc-700', [
                    for (final p in posts)
                      tr(classes: 'hover:bg-zinc-50/60 transition-colors', [
                        td(classes: 'px-6 py-4', [
                          if (p.imageUrl.isNotEmpty)
                            img(src: p.imageUrl, classes: 'w-16 h-9 rounded object-cover border border-zinc-200')
                          else
                            span(classes: 'text-zinc-350 italic', [Component.text('No image')]),
                        ]),
                        td(classes: 'px-6 py-4 font-bold text-zinc-900', [Component.text(p.title)]),
                        td(classes: 'px-6 py-4', [
                          span(
                            classes:
                                'px-2 py-0.5 rounded font-bold text-[9px] uppercase ${p.category == 'promo'
                                    ? 'bg-green-50 text-green-600'
                                    : p.category == 'news'
                                    ? 'bg-indigo-50 text-indigo-600'
                                    : p.category == 'announcement'
                                    ? 'bg-amber-50 text-amber-600'
                                    : 'bg-purple-50 text-purple-600'}',
                            [Component.text(p.category)],
                          ),
                        ]),
                        td(classes: 'px-6 py-4 font-semibold', [
                          Component.text(p.actionType.toUpperCase() + (p.promoCode != null ? ' (${p.promoCode})' : '')),
                        ]),
                        td(classes: 'px-6 py-4', [
                          span(
                            classes:
                                'px-2 py-0.5 rounded font-bold text-[9px] ${p.isActive ? "bg-green-50 text-green-600" : "bg-zinc-100 text-zinc-400"}',
                            [Component.text(p.isActive ? 'ACTIVE' : 'DRAFT')],
                          ),
                        ]),
                        td(classes: 'px-6 py-4 text-right space-x-2', [
                          button(
                            classes:
                                'px-3 py-1.5 bg-zinc-100 hover:bg-zinc-200 text-zinc-700 rounded-xl font-bold transition-all',
                            events: {'click': (_) => _selectPost(p)},
                            [Component.text('Edit')],
                          ),
                          button(
                            classes:
                                'px-3 py-1.5 bg-red-50 hover:bg-red-100 text-red-600 rounded-xl font-bold transition-all',
                            events: {'click': (_) => _deletePost(p.id)},
                            [Component.text('Delete')],
                          ),
                        ]),
                      ]),
                  ]),
                ]);
              },
              loading: () => div(classes: 'p-12 text-center', [
                div(
                  classes: 'animate-spin h-6 w-6 border-2 border-zinc-200 border-t-indigo-500 rounded-full mx-auto',
                  [],
                ),
              ]),
              error: (err, _) => div(classes: 'p-12 text-center text-red-500 font-mono text-xs', [
                Component.text('Error loading listings: $err'),
              ]),
            ),
          ]),
        ]),

        // Right side: Editor Form panel
        div(
          classes: 'lg:col-span-4 bg-white rounded-3xl border border-zinc-200/60 p-6 space-y-6 shadow-sm',
          key: ValueKey(_formVersion),
          [
            div(classes: 'flex justify-between items-center border-b border-zinc-100 pb-3', [
              h2(classes: 'text-sm font-bold text-zinc-800 uppercase tracking-wider', [
                Component.text(_editingId.isEmpty ? 'Create Banner' : 'Edit Banner'),
              ]),
              if (_editingId.isNotEmpty)
                button(
                  classes: 'text-xs font-bold text-zinc-400 hover:text-zinc-600',
                  events: {'click': (_) => _resetForm()},
                  [Component.text('Cancel')],
                ),
            ]),

            // Form inputs
            div(classes: 'space-y-4 text-xs font-semibold text-zinc-500', [
              // Title
              div(classes: 'flex flex-col gap-1.5', [
                label([Component.text('Banner Title *')]),
                input(
                  classes:
                      'px-4 py-3 rounded-xl border border-zinc-200 outline-none focus:border-zinc-350 text-sm font-medium',
                  type: InputType.text,
                  attributes: {'placeholder': 'e.g. 50% Off First Transit Ride!', 'value': _title},
                  events: {'input': (e) => _title = (e.target as dynamic).value as String},
                ),
              ]),

              // Category
              div(classes: 'flex flex-col gap-1.5', [
                label([Component.text('Category')]),
                select(
                  classes:
                      'px-4 py-3 rounded-xl border border-zinc-200 outline-none focus:border-zinc-350 text-sm font-medium bg-white',
                  events: {'change': (e) => _category = (e.target as dynamic).value as String},
                  [
                    option(value: 'news', attributes: _category == 'news' ? {'selected': ''} : {}, [
                      Component.text('News Announcement'),
                    ]),
                    option(value: 'promo', attributes: _category == 'promo' ? {'selected': ''} : {}, [
                      Component.text('Promotion / Discount'),
                    ]),
                    option(value: 'advertisement', attributes: _category == 'advertisement' ? {'selected': ''} : {}, [
                      Component.text('Advertisement'),
                    ]),
                    option(value: 'announcement', attributes: _category == 'announcement' ? {'selected': ''} : {}, [
                      Component.text('Announcement'),
                    ]),
                  ],
                ),
              ]),

              // Content / Body
              div(classes: 'flex flex-col gap-1.5', [
                label([Component.text('Content Description *')]),
                textarea(
                  placeholder: 'Enter announcement details or promo eligibility requirements...',
                  classes:
                      'px-4 py-3 rounded-xl border border-zinc-200 outline-none focus:border-zinc-350 text-sm font-medium h-24 resize-none',
                  events: {'input': (e) => _content = (e.target as dynamic).value as String},
                  [Component.text(_content)],
                ),
              ]),

              // Image URL
              div(classes: 'flex flex-col gap-1.5', [
                label([Component.text('Banner Image URL')]),
                input(
                  classes:
                      'px-4 py-3 rounded-xl border border-zinc-200 outline-none focus:border-zinc-350 text-sm font-medium',
                  type: InputType.text,
                  attributes: {'placeholder': 'e.g. https://images.unsplash.com/...', 'value': _imageUrl},
                  events: {'input': (e) => setState(() => _imageUrl = (e.target as dynamic).value as String)},
                ),
                // File picker for direct computer uploads
                div(
                  classes:
                      'mt-1 flex items-center justify-center border border-dashed border-zinc-250 rounded-2xl p-4 bg-zinc-50 hover:bg-zinc-100 transition-colors relative cursor-pointer',
                  [
                    input(
                      classes: 'absolute inset-0 opacity-0 cursor-pointer w-full h-full',
                      type: InputType.file,
                      attributes: {'accept': 'image/*'},
                      events: {'change': (e) => _handleImageUpload(e as web.Event)},
                    ),
                    div(classes: 'text-center space-y-1 text-[11px] text-zinc-500 font-bold', [
                      span([Component.text('📁 Upload directly from computer')]),
                      p(classes: 'text-[9px] text-zinc-400 font-normal', [
                        Component.text('JPG, PNG, WEBP (auto-compressed)'),
                      ]),
                    ]),
                  ],
                ),
              ]),

              // Action Type
              div(classes: 'flex flex-col gap-1.5', [
                label([Component.text('Tap Action')]),
                select(
                  classes:
                      'px-4 py-3 rounded-xl border border-zinc-200 outline-none focus:border-zinc-350 text-sm font-medium bg-white',
                  events: {'change': (e) => setState(() => _actionType = (e.target as dynamic).value as String)},
                  [
                    option(value: 'none', attributes: _actionType == 'none' ? {'selected': ''} : {}, [
                      Component.text('No action (Static banner)'),
                    ]),
                    option(value: 'promo', attributes: _actionType == 'promo' ? {'selected': ''} : {}, [
                      Component.text('Redeem Promo Code'),
                    ]),
                    option(value: 'link', attributes: _actionType == 'link' ? {'selected': ''} : {}, [
                      Component.text('Open Web/Deep Link'),
                    ]),
                  ],
                ),
              ]),

              // Linked Promo (Conditional)
              if (_actionType == 'promo')
                div(classes: 'flex flex-col gap-1.5', [
                  label([Component.text('Linked Promo Code')]),
                  input(
                    classes:
                        'px-4 py-3 rounded-xl border border-zinc-200 outline-none focus:border-zinc-350 text-sm font-medium uppercase',
                    type: InputType.text,
                    attributes: {'placeholder': 'e.g. TRANSIT50', 'value': _promoCode},
                    events: {'input': (e) => _promoCode = (e.target as dynamic).value as String},
                  ),
                ]),

              // Action URL (Conditional)
              if (_actionType == 'link' || _actionType == 'promo')
                div(classes: 'flex flex-col gap-1.5', [
                  label([Component.text('Action Destination URL (Web link or tranyx:// deep link)')]),
                  input(
                    classes:
                        'px-4 py-3 rounded-xl border border-zinc-200 outline-none focus:border-zinc-350 text-sm font-medium',
                    type: InputType.text,
                    attributes: {'placeholder': 'e.g. https://external.com or tranyx://transit', 'value': _actionUrl},
                    events: {'input': (e) => _actionUrl = (e.target as dynamic).value as String},
                  ),
                ]),

              // Absolute Button Configurations
              div(classes: 'border-t border-zinc-150/60 pt-4 space-y-4', [
                p(classes: 'text-xs font-bold text-zinc-700 uppercase tracking-wider', [
                  Component.text('Embedded Button Overlay'),
                ]),

                div(classes: 'flex flex-col gap-1.5', [
                  label([Component.text('Button Text')]),
                  input(
                    classes:
                        'px-4 py-3 rounded-xl border border-zinc-200 outline-none focus:border-zinc-350 text-sm font-medium',
                    type: InputType.text,
                    attributes: {'placeholder': 'e.g. Claim Now, Visit Site', 'value': _buttonText},
                    events: {'input': (e) => setState(() => _buttonText = (e.target as dynamic).value as String)},
                  ),
                ]),

                if (_buttonText.trim().isNotEmpty) ...[
                  div(classes: 'grid grid-cols-2 gap-4', [
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Left (X) %')]),
                      input(
                        classes: 'px-4 py-3 rounded-xl border border-zinc-200 outline-none text-sm font-medium',
                        type: InputType.number,
                        attributes: {'min': '0', 'max': '100', 'value': _buttonXStr},
                        events: {'input': (e) => setState(() => _buttonXStr = (e.target as dynamic).value as String)},
                      ),
                    ]),
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Top (Y) %')]),
                      input(
                        classes: 'px-4 py-3 rounded-xl border border-zinc-200 outline-none text-sm font-medium',
                        type: InputType.number,
                        attributes: {'min': '0', 'max': '100', 'value': _buttonYStr},
                        events: {'input': (e) => setState(() => _buttonYStr = (e.target as dynamic).value as String)},
                      ),
                    ]),
                  ]),

                  div(classes: 'grid grid-cols-2 gap-4', [
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Width %')]),
                      input(
                        classes: 'px-4 py-3 rounded-xl border border-zinc-200 outline-none text-sm font-medium',
                        type: InputType.number,
                        attributes: {'min': '0', 'max': '100', 'value': _buttonWidthStr},
                        events: {
                          'input': (e) => setState(() => _buttonWidthStr = (e.target as dynamic).value as String),
                        },
                      ),
                    ]),
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Height %')]),
                      input(
                        classes: 'px-4 py-3 rounded-xl border border-zinc-200 outline-none text-sm font-medium',
                        type: InputType.number,
                        attributes: {'min': '0', 'max': '100', 'value': _buttonHeightStr},
                        events: {
                          'input': (e) => setState(() => _buttonHeightStr = (e.target as dynamic).value as String),
                        },
                      ),
                    ]),
                  ]),

                  // Styling configurations
                  p(
                    classes:
                        'text-[11px] font-bold text-zinc-700 uppercase tracking-wider mt-2 pt-2 border-t border-zinc-150/40',
                    [Component.text('Button Colors & Borders')],
                  ),

                  div(classes: 'grid grid-cols-2 gap-4', [
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Fill / Background')]),
                      div(classes: 'flex gap-2 items-center', [
                        input(
                          classes: 'w-8 h-8 rounded-lg border border-zinc-250 outline-none p-0 cursor-pointer',
                          type: InputType.color,
                          attributes: {'value': _buttonBgColor},
                          events: {
                            'input': (e) => setState(() => _buttonBgColor = (e.target as dynamic).value as String),
                          },
                        ),
                        span(classes: 'text-[10px] uppercase font-mono text-zinc-500', [
                          Component.text(_buttonBgColor),
                        ]),
                      ]),
                    ]),
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Text Color')]),
                      div(classes: 'flex gap-2 items-center', [
                        input(
                          classes: 'w-8 h-8 rounded-lg border border-zinc-250 outline-none p-0 cursor-pointer',
                          type: InputType.color,
                          attributes: {'value': _buttonTextColor},
                          events: {
                            'input': (e) => setState(() => _buttonTextColor = (e.target as dynamic).value as String),
                          },
                        ),
                        span(classes: 'text-[10px] uppercase font-mono text-zinc-500', [
                          Component.text(_buttonTextColor),
                        ]),
                      ]),
                    ]),
                  ]),

                  div(classes: 'grid grid-cols-2 gap-4', [
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Border Color')]),
                      div(classes: 'flex gap-2 items-center', [
                        input(
                          classes: 'w-8 h-8 rounded-lg border border-zinc-250 outline-none p-0 cursor-pointer',
                          type: InputType.color,
                          attributes: {'value': _buttonBorderColor},
                          events: {
                            'input': (e) => setState(() => _buttonBorderColor = (e.target as dynamic).value as String),
                          },
                        ),
                        span(classes: 'text-[10px] uppercase font-mono text-zinc-500', [
                          Component.text(_buttonBorderColor),
                        ]),
                      ]),
                    ]),
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Border Width (px)')]),
                      input(
                        classes: 'px-4 py-3 rounded-xl border border-zinc-200 outline-none text-sm font-medium',
                        type: InputType.number,
                        attributes: {'min': '0', 'max': '8', 'value': _buttonBorderWidth},
                        events: {
                          'input': (e) => setState(() => _buttonBorderWidth = (e.target as dynamic).value as String),
                        },
                      ),
                    ]),
                  ]),

                  p(
                    classes:
                        'text-[11px] font-bold text-zinc-700 uppercase tracking-wider mt-2 pt-2 border-t border-zinc-150/40',
                    [Component.text('Button Dimensions & Corners')],
                  ),

                  div(classes: 'grid grid-cols-3 gap-2', [
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Corner Radius')]),
                      input(
                        classes:
                            'px-2 py-3 rounded-xl border border-zinc-200 outline-none text-sm font-medium text-center',
                        type: InputType.number,
                        attributes: {'min': '0', 'max': '32', 'value': _buttonBorderRadius},
                        events: {
                          'input': (e) => setState(() => _buttonBorderRadius = (e.target as dynamic).value as String),
                        },
                      ),
                    ]),
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Padding V')]),
                      input(
                        classes:
                            'px-2 py-3 rounded-xl border border-zinc-200 outline-none text-sm font-medium text-center',
                        type: InputType.number,
                        attributes: {'min': '0', 'max': '24', 'value': _buttonPaddingV},
                        events: {
                          'input': (e) => setState(() => _buttonPaddingV = (e.target as dynamic).value as String),
                        },
                      ),
                    ]),
                    div(classes: 'flex flex-col gap-1.5', [
                      label([Component.text('Padding H')]),
                      input(
                        classes:
                            'px-2 py-3 rounded-xl border border-zinc-200 outline-none text-sm font-medium text-center',
                        type: InputType.number,
                        attributes: {'min': '0', 'max': '48', 'value': _buttonPaddingH},
                        events: {
                          'input': (e) => setState(() => _buttonPaddingH = (e.target as dynamic).value as String),
                        },
                      ),
                    ]),
                  ]),
                ],
              ]),

              // Active / Inactive Checkbox
              div(classes: 'flex items-center gap-2 pt-2', [
                input(
                  classes: 'rounded border-zinc-300 text-indigo-600 focus:ring-indigo-500 h-4 w-4',
                  type: InputType.checkbox,
                  id: 'post-is-active',
                  attributes: _isActive ? {'checked': ''} : {},
                  events: {
                    'change': (e) => _isActive = (e.target as web.HTMLInputElement).checked,
                  },
                ),
                label(
                  classes: 'text-zinc-800 font-bold cursor-pointer select-none',
                  attributes: {'for': 'post-is-active'},
                  [Component.text('Publish Banner immediately (Active)')],
                ),
              ]),
            ]),

            // Save & Reset Buttons
            div(classes: 'flex gap-3', [
              button(
                classes:
                    'flex-1 py-3 text-white rounded-xl font-bold transition-all shadow-md flex items-center justify-center '
                    '${_isSaving ? "bg-zinc-400 cursor-not-allowed" : "bg-indigo-600 hover:bg-indigo-700"}',
                events: _isSaving ? {} : {'click': (_) => _savePost()},
                [
                  if (_isSaving)
                    div(classes: 'animate-spin h-5 w-5 border-2 border-white border-t-transparent rounded-full', [])
                  else
                    Component.text(_editingId.isEmpty ? 'Publish Banner' : 'Save Changes'),
                ],
              ),
              button(
                classes:
                    'px-5 py-3 border border-zinc-200 bg-zinc-50 hover:bg-zinc-100 rounded-xl font-bold transition-all text-zinc-650',
                events: {'click': (_) => _resetForm()},
                [Component.text('Reset')],
              ),
            ]),
          ],
        ),
      ]),
    ]);
  }
}

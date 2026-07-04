import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pos_fnb/models/app_models.dart';
import 'package:pos_fnb/services/supabase_service.dart';
import 'package:pos_fnb/widgets/product_image.dart';

/// Màn hình quản lý món ăn (admin): thêm, sửa, xóa, khôi phục món.
class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
  List<Product> _products = [];
  List<Category> _categories = [];
  bool _loading = true;
  String _search = '';
  int? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SupabaseService.getAllProductsForAdmin(),
      SupabaseService.getProductCategories(),
    ]);
    if (!mounted) return;
    setState(() {
      _products = results[0] as List<Product>;
      _categories = results[1] as List<Category>;
      _loading = false;
    });
  }

  List<Product> get _filtered {
    return _products.where((p) {
      final matchesSearch = _search.trim().isEmpty ||
          p.name.toLowerCase().contains(_search.trim().toLowerCase());
      final matchesCategory = _categoryFilter == null || p.categoryId == _categoryFilter;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  Future<File?> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Chọn từ thư viện'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Chụp ảnh'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return null;
    final picked = await picker.pickImage(source: source, imageQuality: 80);
    return picked == null ? null : File(picked.path);
  }

  Future<Category?> _openCreateCategoryDialog() async {
    final nameCtl = TextEditingController();
    bool isSaving = false;
    return showDialog<Category>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Thêm danh mục', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: nameCtl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tên danh mục', prefixIcon: Icon(Icons.category)),
          ),
          actions: [
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: const Text('HỦY')),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                final name = nameCtl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vui lòng nhập tên danh mục')));
                  return;
                }
                setDialogState(() => isSaving = true);
                final created = await SupabaseService.createProductCategory(name);
                if (ctx.mounted) Navigator.pop(ctx, created);
                if (mounted && created == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Tạo danh mục thất bại'), backgroundColor: Colors.red));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('LƯU', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProductDialog({Product? existing}) async {
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final priceCtl = TextEditingController(
        text: existing != null ? existing.price.toStringAsFixed(0) : '');
    Category? selectedCategory = existing == null
        ? (_categories.isNotEmpty ? _categories.first : null)
        : _categories.firstWhere(
          (c) => c.id == existing.categoryId,
      orElse: () => _categories.isNotEmpty ? _categories.first : Category(id: 0, name: existing.categoryName),
    );
    File? pickedImage;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing == null ? 'Thêm món' : 'Sửa món',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: 'Tên món', prefixIcon: Icon(Icons.fastfood)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Giá bán', suffixText: '₫', prefixIcon: Icon(Icons.monetization_on)),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<Category>(
                        value: selectedCategory,
                        decoration: const InputDecoration(labelText: 'Danh mục', prefixIcon: Icon(Icons.category)),
                        items: _categories
                            .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => selectedCategory = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          final newCategory = await _openCreateCategoryDialog();
                          if (newCategory != null) {
                            setDialogState(() {
                              _categories.add(newCategory);
                              selectedCategory = newCategory;
                            });
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.add, color: Colors.orange),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final f = await _pickImage();
                    if (f != null) setDialogState(() => pickedImage = f);
                  },
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black26),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: pickedImage != null
                        ? Image.file(pickedImage!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                        : existing?.imageUrl != null
                        ? ProductImage(imageUrl: existing!.imageUrl, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                        : const Center(child: Icon(Icons.add_a_photo, color: Colors.grey)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: const Text('HỦY')),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                final price = double.tryParse(priceCtl.text.replaceAll('.', '').replaceAll(',', ''));
                if (nameCtl.text.trim().isEmpty || price == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vui lòng nhập đủ tên và giá hợp lệ')));
                  return;
                }
                setDialogState(() => isSaving = true);

                String imageUrl = existing?.imageUrl ?? 'https://picsum.photos/200';
                if (pickedImage != null) {
                  final uploaded = await SupabaseService.uploadProductImage(pickedImage!);
                  if (uploaded != null) imageUrl = uploaded;
                }

                final product = Product(
                  id: existing?.id ?? DateTime.now().millisecondsSinceEpoch,
                  name: nameCtl.text.trim(),
                  price: price,
                  imageUrl: imageUrl,
                  categoryName: selectedCategory?.name ?? '',
                  categoryId: selectedCategory?.id,
                );

                final ok = existing == null
                    ? await SupabaseService.saveProduct(product)
                    : await SupabaseService.updateProduct(product);

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? (existing == null ? 'Đã thêm món' : 'Đã cập nhật món')
                        : 'Có lỗi xảy ra, vui lòng thử lại'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ));
                  _loadData();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: isSaving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(existing == null ? 'THÊM MÓN' : 'LƯU', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xóa món?'),
        content: Text('Ẩn "${product.name}" khỏi menu? Bạn có thể khôi phục lại sau.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('XÓA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await SupabaseService.deleteProduct(product.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Đã xóa món' : 'Xóa thất bại'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) _loadData();
  }

  Future<void> _restoreProduct(Product product) async {
    final ok = await SupabaseService.setProductAvailability(product.id, true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Đã khôi phục món' : 'Khôi phục thất bại'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('Quản lý món ăn', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orangeAccent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProductDialog(),
        backgroundColor: Colors.green,
        icon: const Icon(Icons.add),
        label: const Text('Thêm món'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Tìm món...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _CategoryFilterChip(
                  label: 'Tất cả',
                  selected: _categoryFilter == null,
                  onTap: () => setState(() => _categoryFilter = null),
                ),
                ..._categories.map((c) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _CategoryFilterChip(
                    label: c.name,
                    selected: _categoryFilter == c.id,
                    onTap: () => setState(() => _categoryFilter = c.id),
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? const Center(child: Text('Không tìm thấy món nào'))
                : RefreshIndicator(
              onRefresh: _loadData,
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemCount: _filtered.length,
                itemBuilder: (context, i) {
                  final p = _filtered[i];
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Opacity(
                                opacity: p.isAvailable ? 1 : 0.4,
                                child: ProductImage(imageUrl: p.imageUrl, fit: BoxFit.cover),
                              ),
                              if (!p.isAvailable)
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('Đã ẩn',
                                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Material(
                                  color: Colors.white,
                                  shape: const CircleBorder(),
                                  elevation: 2,
                                  child: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 18),
                                    onSelected: (v) {
                                      if (v == 'edit') _openProductDialog(existing: p);
                                      if (v == 'delete') _deleteProduct(p);
                                      if (v == 'restore') _restoreProduct(p);
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Sửa'))),
                                      if (p.isAvailable)
                                        const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Xóa', style: TextStyle(color: Colors.red))))
                                      else
                                        const PopupMenuItem(value: 'restore', child: ListTile(leading: Icon(Icons.restore, color: Colors.green), title: Text('Khôi phục', style: TextStyle(color: Colors.green)))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: p.isAvailable ? Colors.black : Colors.grey.shade500,
                                    )),
                                const SizedBox(height: 2),
                                Text(p.categoryName, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                const SizedBox(height: 4),
                                Text(currencyFormat.format(p.price),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: p.isAvailable ? Colors.orange : Colors.grey.shade400,
                                      fontSize: 13,
                                    )),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryFilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.orange : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
// NOTE: ObjectBox dependency disabled - migrating to Google AI Edge RAG
// import 'package:objectbox/objectbox.dart';

// Legacy ObjectBox entity - will be replaced by AI Edge RAG documents
// @Entity()
class Document {
  // @Id()
  int id = 0;

  String textContent;

  // @Property(type: PropertyType.floatVector)
  // @HnswIndex(dimensions: 384)  // Keep at 384 to support both MobileBERT and fallback embeddings
  List<double>? embedding;

  // @Property(type: PropertyType.date)
  DateTime? createdAt;

  String? metadata;

  Document({
    this.id = 0,
    this.textContent = '',
    this.embedding,
    this.createdAt,
    this.metadata,
  });

  @override
  String toString() {
    return 'Document{id: $id, textContent: $textContent, embedding: ${embedding?.length ?? 0} dims, createdAt: $createdAt}';
  }
}

// Represents one exercise returned by GET /exercises/.
// The endpoint returns a list; each item in that list becomes an Exercise.
class Exercise {
  // These fields describe one exercise.
  // final means each field is initialized once and cannot be reassigned later.
  // The types are non-nullable: an Exercise must have all three values.
  // Exercise IDs are integers in the API. Names and categories are text.
  final int id;
  final String name;
  final String category;

  // The constructor creates an Exercise from values supplied by the caller.
  // Braces {} make these named arguments, so calls use id: ..., name: ..., etc.
  // required means none of the arguments can be omitted.
  // this.id assigns the supplied id directly to this object's id field;
  // this.name and this.category do the same for their corresponding fields.
  // const allows constant instances when used in a constant context. This
  // constructor also works normally with runtime values received from the API.
  const Exercise({
    required this.id,
    required this.name,
    required this.category,
  });

  // A named factory constructor provides another way to create an Exercise.
  // fromJson is a conventional name; our service must explicitly call it.
  // The input is already decoded: it is a Map, not the raw JSON response text.
  // Map<String, dynamic> means string keys with values of potentially different
  // types, such as {'id': 1, 'name': 'Squat', 'category': 'strength'}.
  factory Exercise.fromJson(Map<String, dynamic> json) {
    // Read each API key and pass its value to the constructor above.
    // as int / as String check the runtime type; they do not convert values.
    // For example, the string '1' cannot be cast to int. Missing keys or values
    // of the wrong type fail here rather than creating an incomplete Exercise.
    return Exercise(
      id: json['id'] as int,
      name: json['name'] as String,
      category: json['category'] as String,
    );
  }
}

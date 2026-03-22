Core Guidelines from "Clean Code":
Meaningful Names: Use intention-revealing, pronounceable, and searchable names.
Functions: Keep them small, restricted to 1–2 levels of indentation, and doing one thing.
Arguments: Prefer 0–2 arguments; avoid passing booleans or using flag arguments.
Comments: Avoid them when possible; code should explain itself. If necessary, use them to explain intent rather than excuses for bad code.
DRY Principle: Don’t Repeat Yourself—remove code duplication.
Error Handling: Use exceptions rather than returning error codes.
Formatting: Maintain vertical density and order, with dependent functions close to each other. 

Structural & Design Guidelines:
SOLID Principles: Abide by SOLID object-oriented design principles.
Abstraction Levels: Every line in a function should be at the same level of abstraction.
Test-Driven Development (TDD): Aim for high test coverage, using TDD to create maintainable code.
Red Green development of new features is best 
Screaming Architecture: Folder structures should reveal the system's purpose (use cases) rather than frameworks (e.g., controllers/models). 

Clean Test Coverage: Treat 100% test coverage as an aspirational goal. 

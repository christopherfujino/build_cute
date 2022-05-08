import 'dart:convert';
import 'dart:io' as io;

import 'parser.dart';

typedef Printer = void Function(String);

class Interpreter {
  Interpreter({
    required this.config,
    required this.env,
  });

  final Config config;
  final InterpreterEnv env;

  final Map<String, FunctionDecl> _functionBindings =
      <String, FunctionDecl>{};

  final Map<String, TargetDecl> _targetBindings = <String, TargetDecl>{};

  static const Map<String, ExtFuncDecl> _externalFunctions =
      <String, ExtFuncDecl>{
    'run': RunFuncDecl(),
    'sequence': SequenceFuncDecl(),
  };

  //visibleForOverriding
  void stdoutPrint(String msg) {
    io.stdout.writeln(msg);
  }

  //visibleForOverriding
  void stderrPrint(String msg) {
    io.stderr.writeln(msg);
  }

  Future<void> interpret(String targetName) async {
    // Register declarations
    _registerDeclarations();

    // interpret target
    await _interpretTarget(targetName, <String>{});
  }

  Future<void> _interpretTarget(String name, Set<String> visitedTargets) async {
    visitedTargets.add(name);
    // Determine target to run from [targetName]
    final TargetDecl? target = _targetBindings[name];
    if (target == null) {
      _throwRuntimeError('There is no defined target named $name');
    }

    for (final IdentifierRef dep in target.deps) {
      if (!visitedTargets.contains(dep.name)) {
        await _interpretTarget(dep.name, visitedTargets);
      }
    }

    stdoutPrint('\nExecuting target "$name"...\n');

    for (final Stmt stmt in target.statements) {
      await _stmt(stmt);
    }
  }

  Future<void> _stmt(Stmt stmt) async {
    if (stmt is FunctionExitStmt) {
      _throwRuntimeError('Unimplemented statement type ${stmt.runtimeType}');
    }
    if (stmt is BareStmt) {
      await _bareStatement(stmt);
      return;
    }
    _throwRuntimeError('Unimplemented statement type ${stmt.runtimeType}');
  }

  void _registerDeclarations() {
    for (final Decl decl in config.declarations) {
      if (decl is TargetDecl) {
        // TODO should check globally for any identifier with this name
        if (_targetBindings.containsKey(decl.name)) {
          _throwRuntimeError('Duplicate target named ${decl.name}');
        }
        _targetBindings[decl.name] = decl;
      } else {
        _throwRuntimeError('Unknown declaration type ${decl.runtimeType}');
      }
    }
  }

  Future<void> _bareStatement(BareStmt statement) async {
    await _expr(statement.expression);
  }

  Future<Object?> _expr(Expr expr) {
    if (expr is CallExpr) {
      return _callExpr(expr);
    }

    if (expr is ListLiteral) {
      return _list(expr.elements);
    }

    if (expr is StringLiteral) {
      return _stringLiteral(expr);
    }
    _throwRuntimeError('Unimplemented expression type ${expr.runtimeType}');
  }

  Future<Object?> _callExpr(CallExpr expr) async {
    if (_externalFunctions.containsKey(expr.name)) {
      final ExtFuncDecl func = _externalFunctions[expr.name]!;
      await func.interpret(
        argExpressions: expr.argList,
        interpreter: this,
        env: env,
      );
      return null;
    }

    final FunctionDecl? func = _functionBindings[expr.name];
    if (func == null) {
      _throwRuntimeError('Tried to call undeclared function ${expr.name}');
    }
    for (final Stmt stmt in func.statements) {
      if (stmt is FunctionExitStmt) {
        return _expr(stmt.returnValue);
      }
      await _stmt(stmt);
    }
    return null;
  }

  Future<List<Object?>> _list(List<Expr> expressions) async {
    final List<Object?> elements = <Object?>[];
    for (final Expr element in expressions) {
      elements.add(await _expr(element));
    }
    return elements;
  }

  Future<String> _stringLiteral(StringLiteral expr) {
    return Future<String>.value(expr.value);
  }

  Future<int> runProcess({
    required String command,
    required io.Directory workingDir,
  }) async {
    stdoutPrint('Running command "$command"...');
    final List<String> commandParts = command.split(' ');
    final String executable = commandParts.first;
    final List<String> rest = commandParts.sublist(1);
    final io.Process process = await io.Process.start(
      executable,
      rest,
      workingDirectory: workingDir.absolute.path,
    );
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      stdoutPrint(line);
    });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      stderrPrint(line);
    });
    return process.exitCode;
  }
}

class InterpreterEnv {
  const InterpreterEnv({
    required this.workingDir,
  });

  final io.Directory workingDir;
}

/// An external [FunctionDecl].
abstract class ExtFuncDecl extends FunctionDecl {
  const ExtFuncDecl({
    required super.name,
  }) : super(statements: const <Stmt>[]);

  Future<void> interpret({
    required List<Expr> argExpressions,
    required Interpreter interpreter,
    required InterpreterEnv env,
  });
}

class RunFuncDecl extends ExtFuncDecl {
  const RunFuncDecl() : super(name: 'run');

  @override
  Future<void> interpret({
    required List<Expr> argExpressions,
    required Interpreter interpreter,
    required InterpreterEnv env,
  }) async {
    final List<String> args = <String>[];

    for (final Expr argExpr in argExpressions) {
      final Object? value = await interpreter._expr(argExpr);
      if (value is! String) {
        _throwRuntimeError(
          'Expected an arg of type String, got ${value.runtimeType}',
        );
      }
      args.add(value);
    }
    final String command = args.first;
    final int exitCode = await interpreter.runProcess(
      command: command,
      workingDir: env.workingDir,
    );
    if (exitCode != 0) {
      _throwRuntimeError('"${args.join(' ')}" exited with code $exitCode');
    }
  }
}

class SequenceFuncDecl extends ExtFuncDecl {
  const SequenceFuncDecl() : super(name: 'sequence');

  @override
  Future<void> interpret({
    required List<Expr> argExpressions,
    required Interpreter interpreter,
    required InterpreterEnv env,
  }) async {
    if (argExpressions.length != 1) {
      _throwRuntimeError('Expected one arg, got $argExpressions');
    }
    final Object? value = await interpreter._expr(argExpressions.first);
    if (value is! List<Object?>) {
      _throwRuntimeError(
        'Expected an arg of type List, got ${value.runtimeType}',
      );
    }

    for (final Object? command in value) {
      if (command is! String) {
        _throwRuntimeError('Foo bar');
      }
      final int exitCode = await interpreter.runProcess(
        command: command,
        workingDir: env.workingDir,
      );
      if (exitCode != 0) {
        _throwRuntimeError('Command "$command" exited with non-zero');
      }
    }
  }
}

// TODO accept token
Never _throwRuntimeError(String message) => throw RuntimeError(message);

class RuntimeError implements Exception {
  const RuntimeError(this.message);

  final String message;

  @override
  String toString() => message;
}

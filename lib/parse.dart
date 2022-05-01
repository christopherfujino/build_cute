import 'scanner.dart';
import 'source_code.dart';

class Config {
  const Config(this.declarations);

  final List declarations;
}

class Parser {
  Parser({
    required this.tokenList,
    required this.source,
  });

  final List<Token> tokenList;
  final SourceCode source;

  /// Index for current token being parsed.
  int _index = 0;
  Token? get _currentToken {
    if (_index >= tokenList.length) {
      return null;
    }
    return tokenList[_index];
  }

  Future<Config> parse() async {
    final List declarations = [];
    Declaration? currentDeclaration = _parseDeclaration();
    while (currentDeclaration != null) {
      declarations.add(currentDeclaration);
      currentDeclaration = _parseDeclaration();
    }

    return Config(declarations);
  }

  /// Parses [TargetDeclaration].
  Declaration? _parseDeclaration() {
    final Token currentToken = _currentToken!;
    switch (currentToken.type) {
      case TokenType.target:
        return _parseTargetDeclaration();
      default:
        _throwParseError(
          currentToken,
          'Unknown declaration type ${currentToken.type.name}',
        );
    }
  }

  Never _throwParseError(Token token, String message) {
    throw ParseError(
      '\n${source.getDebugMessage(token.line, token.char)}\n'
      'Parse error: $message [${token.line}, ${token.char}]\n',
    );
  }

  /// Parse a [TargetDeclaration].
  ///
  /// target_declaration ::= "target", identifier, "(", ")", "{", statement*, "}"
  TargetDeclaration _parseTargetDeclaration() {
    _consume(TokenType.target);
    final StringToken name = _consume(TokenType.identifier) as StringToken;

    _consume(TokenType.openParen);
    // TODO argList
    _consume(TokenType.closeParen);
    _consume(TokenType.openCurlyBracket);
    final List<Statement> statements = <Statement>[];
    while (_currentToken?.type != TokenType.closeCurlyBracket) {
      statements.add(_parseStatement());
    }

    return TargetDeclaration(
      name: name.value,
      statements: statements,
    );
  }

  Statement _parseStatement() {
    Statement statement = _parseExpressionStatement();
    // TODO implement other statements
    return statement;
  }

  // bare_statement ::= expression, ";"
  BareStatement _parseExpressionStatement() {
    final Expression expression = _parseExpression();
    if (_currentToken!.type != TokenType.semicolon) {
      _throwParseError(_currentToken!, 'Parse error: at ${_currentToken}');
    }
    return BareStatement(expression: expression);
  }

  // Expressions

  Expression _parseExpression() {
    //_tokenLookahead();
    Expression expression = _parseCallExpression();
    return expression;
  }

  // call_expression ::= identifier, "(", arg_list?, ")"
  CallExpression _parseCallExpression() {
    final StringToken name = _consume(TokenType.identifier) as StringToken;
    List<Expression>? argList;
    _consume(TokenType.openParen);
    if (_currentToken?.type != TokenType.closeParen) {
      argList = _parseArgList();
    }
    _consume(TokenType.closeParen);
    return CallExpression(
      name.value,
      argList ?? const <Expression>[],
    );
  }

  /// Parses expressions (comma delimited) until a [TokenType.closeParen] is
  /// reached (but not consumed).
  List<Expression> _parseArgList() {
    final List<Expression> list = <Expression>[];
    while (_currentToken?.type != TokenType.closeParen) {
      list.add(_parseExpression());
      if (_currentToken?.type == TokenType.closeParen) {
        break;
      }
      // else this should be a comma
      _consume(TokenType.comma);
    }

    return list;
  }

  /// Consume and return the next token iff it matches [type].
  ///
  /// Throws [Exception] if the type is not correct.
  Token _consume(TokenType type) {
    // coerce type as this should only be called if you know what's there.
    final Token consumedToken = _currentToken!;
    if (consumedToken.type != type) {
      _throwParseError(consumedToken, 'Expected a ${type.name}, got a ${consumedToken.type.name}');
    }
    _index += 1;
    return consumedToken;
  }

  /// Verifies whether or not the [tokenTypes] are next in the [tokenList].
  ///
  /// Does not mutate [_index].
  bool _tokenLookahead(List<TokenType> tokenTypes) {
    // note must use >
    // Consider a tokenlist of 4 tokens: [a, b, c, d]
    // where _index == 1 (b)
    // and tokenTypes has 3 elements (b, c, d)
    // this is valid, thus 1 + 3 == 4, not >
    if (_index + tokenTypes.length > tokenList.length) {
      // tokenTypes reaches beyond the end of the list, not possible
      return false;
    }
    for (int i = 0; i < tokenTypes.length; i += 1) {
      if (tokenList[_index + i].type != tokenTypes[i]) {
        return false;
      }
    }
    return true;
  }
}

abstract class Declaration {
  Declaration({
    required this.name,
  });

  final String name;
}

class TargetDeclaration extends Declaration {
  TargetDeclaration({
    required super.name,
    required this.statements,
  });

  final Iterable<Statement> statements;
}

abstract class Statement {}

class BareStatement extends Statement {
  BareStatement({required this.expression});

  final Expression expression;
}

abstract class Expression {}

class CallExpression extends Expression {
  CallExpression(this.name, this.argList);

  final String name;

  List<Expression> argList;
}

class ArgList {}

class ParseError implements Exception {
  const ParseError(this.message);

  final String message;

  @override
  String toString() => message;
}

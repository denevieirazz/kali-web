import { TokenType } from './types';
import type { Token } from './types';


export class Lexer {
  private source: string;
  private cursor: number = 0;
  private line: number = 1;
  private column: number = 1;

  private static readonly KEYWORDS: Record<string, TokenType> = {
    'let': TokenType.Let,
    'fn': TokenType.Fn,
    'if': TokenType.If,
    'else': TokenType.Else,
    'while': TokenType.While,
    'for': TokenType.For,
    'return': TokenType.Return,
    'system': TokenType.System,
    'true': TokenType.Boolean,
    'false': TokenType.Boolean,
    'null': TokenType.Null,
  };

  constructor(source: string) {
    this.source = source;
  }

  tokenize(): Token[] {
    const tokens: Token[] = [];
    while (!this.isAtEnd()) {
      const token = this.nextToken();
      if (token) tokens.push(token);
    }
    tokens.push(this.makeToken(TokenType.EOF, ''));
    return tokens;
  }

  private nextToken(): Token | null {
    this.skipWhitespaceAndComments();
    if (this.isAtEnd()) return null;

    const char = this.peek();

    // Identifiers & Keywords
    if (this.isAlpha(char)) return this.identifier();

    // Numbers
    if (this.isDigit(char)) return this.number();

    // Strings
    if (char === '"' || char === "'") return this.string(char);

    // Symbols & Operators
    this.advance();
    switch (char) {
      case '(': return this.makeToken(TokenType.OpenParen, '(');
      case ')': return this.makeToken(TokenType.CloseParen, ')');
      case '{': return this.makeToken(TokenType.OpenBrace, '{');
      case '}': return this.makeToken(TokenType.CloseBrace, '}');
      case '[': return this.makeToken(TokenType.OpenBracket, '[');
      case ']': return this.makeToken(TokenType.CloseBracket, ']');
      case ',': return this.makeToken(TokenType.Comma, ',');
      case ';': return this.makeToken(TokenType.Semicolon, ';');
      case ':':
        if (this.match(':')) return this.makeToken(TokenType.DoubleColon, '::');
        return this.makeToken(TokenType.Colon, ':');
      case '=':
        if (this.match('=')) return this.makeToken(TokenType.DoubleEquals, '==');
        return this.makeToken(TokenType.Equals, '=');
      case '!':
        if (this.match('=')) return this.makeToken(TokenType.NotEquals, '!=');
        return this.makeToken(TokenType.Not, '!');
      case '>':
        if (this.match('=')) return this.makeToken(TokenType.GreaterEquals, '>=');
        return this.makeToken(TokenType.Greater, '>');
      case '<':
        if (this.match('=')) return this.makeToken(TokenType.LessEquals, '<=');
        return this.makeToken(TokenType.Less, '<');
      case '+': return this.makeToken(TokenType.Plus, '+');
      case '-': return this.makeToken(TokenType.Minus, '-');
      case '*': return this.makeToken(TokenType.Asterisk, '*');
      case '/': return this.makeToken(TokenType.Slash, '/');
      case '%': return this.makeToken(TokenType.Percent, '%');
      case '&':
        if (this.match('&')) return this.makeToken(TokenType.And, '&&');
        break;
      case '|':
        if (this.match('|')) return this.makeToken(TokenType.Or, '||');
        break;
    }

    throw new Error(`Unexpected character: '${char}' at line ${this.line}, col ${this.column}`);
  }

  private identifier(): Token {
    const start = this.cursor;
    while (this.isAlphaNumeric(this.peek())) this.advance();
    const value = this.source.substring(start, this.cursor);
    const type = Lexer.KEYWORDS[value] || TokenType.Identifier;
    return this.makeToken(type, value);
  }

  private number(): Token {
    const start = this.cursor;
    while (this.isDigit(this.peek())) this.advance();

    // Fractional part
    if (this.peek() === '.' && this.isDigit(this.peekNext())) {
      this.advance(); // .
      while (this.isDigit(this.peek())) this.advance();
    }

    const value = this.source.substring(start, this.cursor);
    return this.makeToken(TokenType.Number, value);
  }

  private string(quote: string): Token {
    this.advance(); // Consume opening quote
    const start = this.cursor;
    while (this.peek() !== quote && !this.isAtEnd()) {
      if (this.peek() === '\n') this.line++;
      this.advance();
    }

    if (this.isAtEnd()) throw new Error(`Unterminated string at line ${this.line}`);

    const value = this.source.substring(start, this.cursor);
    this.advance(); // Consume closing quote
    return this.makeToken(TokenType.String, value);
  }

  private skipWhitespaceAndComments() {
    while (!this.isAtEnd()) {
      const char = this.peek();
      switch (char) {
        case ' ':
        case '\r':
        case '\t':
          this.advance();
          break;
        case '\n':
          this.line++;
          this.column = 1;
          this.advance();
          break;
        case '/':
          if (this.peekNext() === '/') {
            // Comment until end of line
            while (this.peek() !== '\n' && !this.isAtEnd()) this.advance();
          } else {
            return;
          }
          break;
        default:
          return;
      }
    }
  }

  // Helpers
  private isAtEnd(): boolean { return this.cursor >= this.source.length; }
  private peek(): string { return this.source[this.cursor] || ''; }
  private peekNext(): string { return this.source[this.cursor + 1] || ''; }

  private advance(): string {
    const char = this.source[this.cursor++];
    this.column++;
    return char;
  }

  private match(expected: string): boolean {
    if (this.peek() !== expected) return false;
    this.advance();
    return true;
  }

  private isDigit(c: string): boolean { return c >= '0' && c <= '9'; }
  private isAlpha(c: string): boolean {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '_';
  }
  private isAlphaNumeric(c: string): boolean { return this.isAlpha(c) || this.isDigit(c); }

  private makeToken(type: TokenType, value: string): Token {
    return { type, value, line: this.line, column: this.column - value.length };
  }
}

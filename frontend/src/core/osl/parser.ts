import { TokenType } from './types';
import type { 
  Token, Program, Statement, Expression, 
  VariableDeclaration, FunctionDeclaration, IfStatement, 
  WhileStatement, ReturnStatement, BlockStatement, 
  CallExpression, Identifier, ExpressionStatement
} from './types';


export class Parser {
  private tokens: Token[];
  private current: number = 0;

  constructor(tokens: Token[]) {
    this.tokens = tokens;
  }

  parse(): Program {
    const body: Statement[] = [];
    while (!this.isAtEnd()) {
      body.push(this.declaration());
    }
    return { type: 'Program', body };
  }

  // ── Declarations ───────────────────────────────────────────────────────────

  private declaration(): Statement {
    try {
      if (this.match(TokenType.Let)) return this.varDeclaration();
      if (this.match(TokenType.Fn)) return this.functionDeclaration();
      return this.statement();
    } catch (error) {
      this.synchronize();
      throw error;
    }
  }

  private varDeclaration(): VariableDeclaration {
    const name = this.consume(TokenType.Identifier, "Expect variable name.");
    let init;
    if (this.match(TokenType.Equals)) {
      init = this.expression();
    }
    this.consume(TokenType.Semicolon, "Expect ';' after variable declaration.");
    return { type: 'VariableDeclaration', id: { type: 'Identifier', name: name.value }, init };
  }

  private functionDeclaration(): FunctionDeclaration {
    const name = this.consume(TokenType.Identifier, "Expect function name.");
    this.consume(TokenType.OpenParen, "Expect '(' after function name.");
    const params: Identifier[] = [];
    if (!this.check(TokenType.CloseParen)) {
      do {
        params.push({ type: 'Identifier', name: this.consume(TokenType.Identifier, "Expect parameter name.").value });
      } while (this.match(TokenType.Comma));
    }
    this.consume(TokenType.CloseParen, "Expect ')' after parameters.");
    this.consume(TokenType.OpenBrace, "Expect '{' before function body.");
    const body = this.blockStatement();
    return { type: 'FunctionDeclaration', id: { type: 'Identifier', name: name.value }, params, body };
  }

  // ── Statements ─────────────────────────────────────────────────────────────

  private statement(): Statement {
    if (this.match(TokenType.If)) return this.ifStatement();
    if (this.match(TokenType.While)) return this.whileStatement();
    if (this.match(TokenType.Return)) return this.returnStatement();
    if (this.match(TokenType.OpenBrace)) return this.blockStatement();
    return this.expressionStatement();
  }

  private ifStatement(): IfStatement {
    this.consume(TokenType.OpenParen, "Expect '(' after 'if'.");
    const test = this.expression();
    this.consume(TokenType.CloseParen, "Expect ')' after if condition.");
    const consequent = this.statement();
    let alternate;
    if (this.match(TokenType.Else)) {
      alternate = this.statement();
    }
    return { type: 'IfStatement', test, consequent, alternate };
  }

  private whileStatement(): WhileStatement {
    this.consume(TokenType.OpenParen, "Expect '(' after 'while'.");
    const test = this.expression();
    this.consume(TokenType.CloseParen, "Expect ')' after while condition.");
    const body = this.statement();
    return { type: 'WhileStatement', test, body };
  }

  private returnStatement(): ReturnStatement {
    let argument;
    if (!this.check(TokenType.Semicolon)) {
      argument = this.expression();
    }
    this.consume(TokenType.Semicolon, "Expect ';' after return value.");
    return { type: 'ReturnStatement', argument };
  }

  private blockStatement(): BlockStatement {
    const body: Statement[] = [];
    while (!this.check(TokenType.CloseBrace) && !this.isAtEnd()) {
      body.push(this.declaration());
    }
    this.consume(TokenType.CloseBrace, "Expect '}' after block.");
    return { type: 'BlockStatement', body };
  }

  private expressionStatement(): ExpressionStatement {
    const expression = this.expression();
    this.consume(TokenType.Semicolon, "Expect ';' after expression.");
    return { type: 'ExpressionStatement', expression };
  }

  // ── Expressions (Precedence) ───────────────────────────────────────────────

  private expression(): Expression {
    return this.assignment();
  }

  private assignment(): Expression {
    const expr = this.or();
    if (this.match(TokenType.Equals)) {
      const value = this.assignment();
      if (expr.type === 'Identifier') {
        // Transformar em uma atribuição (BinaryExpression com '=') ou nó específico
        return { type: 'BinaryExpression', left: expr, operator: '=', right: value };
      }
      throw new Error("Invalid assignment target.");
    }
    return expr;
  }

  private or(): Expression {
    let expr = this.and();
    while (this.match(TokenType.Or)) {
      const operator = '||';
      const right = this.and();
      expr = { type: 'BinaryExpression', left: expr, operator, right };
    }
    return expr;
  }

  private and(): Expression {
    let expr = this.equality();
    while (this.match(TokenType.And)) {
      const operator = '&&';
      const right = this.equality();
      expr = { type: 'BinaryExpression', left: expr, operator, right };
    }
    return expr;
  }

  private equality(): Expression {
    let expr = this.comparison();
    while (this.match(TokenType.DoubleEquals, TokenType.NotEquals)) {
      const operator = this.previous().value;
      const right = this.comparison();
      expr = { type: 'BinaryExpression', left: expr, operator, right };
    }
    return expr;
  }

  private comparison(): Expression {
    let expr = this.term();
    while (this.match(TokenType.Greater, TokenType.GreaterEquals, TokenType.Less, TokenType.LessEquals)) {
      const operator = this.previous().value;
      const right = this.term();
      expr = { type: 'BinaryExpression', left: expr, operator, right };
    }
    return expr;
  }

  private term(): Expression {
    let expr = this.factor();
    while (this.match(TokenType.Plus, TokenType.Minus)) {
      const operator = this.previous().value;
      const right = this.factor();
      expr = { type: 'BinaryExpression', left: expr, operator, right };
    }
    return expr;
  }

  private factor(): Expression {
    let expr = this.unary();
    while (this.match(TokenType.Slash, TokenType.Asterisk, TokenType.Percent)) {
      const operator = this.previous().value;
      const right = this.unary();
      expr = { type: 'BinaryExpression', left: expr, operator, right };
    }
    return expr;
  }

  private unary(): Expression {
    if (this.match(TokenType.Not, TokenType.Minus)) {
      const operator = this.previous().value;
      const right = this.unary();
      return { type: 'UnaryExpression', operator, argument: right };
    }
    return this.call();
  }

  private call(): Expression {
    let expr = this.primary();
    while (true) {
      if (this.match(TokenType.OpenParen)) {
        expr = this.finishCall(expr);
      } else if (this.match(TokenType.DoubleColon)) {
         // System Call logic: item::method()
         if (expr.type !== 'Identifier') {
           throw new Error("Expect identifier before '::'.");
         }
         const method = this.consume(TokenType.Identifier, "Expect method name after '::'.");
         this.consume(TokenType.OpenParen, "Expect '(' after method name.");
         const args = this.arguments();
         this.consume(TokenType.CloseParen, "Expect ')' after arguments.");
         expr = { 
           type: 'SystemCallExpression', 
           module: expr.name, 
           method: method.value, 
           arguments: args 
         };

      } else {
        break;
      }
    }
    return expr;
  }

  private finishCall(callee: Expression): CallExpression {
    const args = this.arguments();
    this.consume(TokenType.CloseParen, "Expect ')' after arguments.");
    if (callee.type !== 'Identifier') throw new Error("Callee must be an identifier.");
    return { type: 'CallExpression', callee, arguments: args };
  }

  private arguments(): Expression[] {
    const args: Expression[] = [];
    if (!this.check(TokenType.CloseParen)) {
      do {
        args.push(this.expression());
      } while (this.match(TokenType.Comma));
    }
    return args;
  }

  private primary(): Expression {
    if (this.match(TokenType.Boolean)) return { type: 'BooleanLiteral', value: this.previous().value === 'true' };
    if (this.match(TokenType.Null)) return { type: 'NullLiteral' };
    if (this.match(TokenType.Number)) return { type: 'NumericLiteral', value: parseFloat(this.previous().value) };
    if (this.match(TokenType.String)) return { type: 'StringLiteral', value: this.previous().value };
    if (this.match(TokenType.System)) return { type: 'Identifier', name: 'system' }; // Virtual identifier for system calls
    if (this.match(TokenType.Identifier)) return { type: 'Identifier', name: this.previous().value };

    if (this.match(TokenType.OpenParen)) {
      const expr = this.expression();
      this.consume(TokenType.CloseParen, "Expect ')' after expression.");
      return expr;
    }

    throw new Error(`Expect expression at line ${this.peek().line}, col ${this.peek().column}`);
  }

  // ── Utils ──────────────────────────────────────────────────────────────────

  private match(...types: TokenType[]): boolean {
    for (const type of types) {
      if (this.check(type)) {
        this.advance();
        return true;
      }
    }
    return false;
  }

  private consume(type: TokenType, message: string): Token {
    if (this.check(type)) return this.advance();
    throw new Error(`${message} at line ${this.peek().line}, col ${this.peek().column}`);
  }

  private check(type: TokenType): boolean {
    if (this.isAtEnd()) return false;
    return this.peek().type === type;
  }

  private advance(): Token {
    if (!this.isAtEnd()) this.current++;
    return this.previous();
  }

  private isAtEnd(): boolean { return this.peek().type === TokenType.EOF; }
  private peek(): Token { return this.tokens[this.current]; }
  private previous(): Token { return this.tokens[this.current - 1]; }

  private synchronize() {
    this.advance();
    while (!this.isAtEnd()) {
      if (this.previous().type === TokenType.Semicolon) return;
      switch (this.peek().type) {
        case TokenType.Let:
        case TokenType.Fn:
        case TokenType.If:
        case TokenType.While:
        case TokenType.Return:
          return;
      }
      this.advance();
    }
  }
}

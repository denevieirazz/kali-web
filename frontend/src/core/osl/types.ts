// ============================================
// OSL Type Definitions - Tokens & AST Nodes
// ============================================

export const TokenType = {
  // Literals
  Number: 'Number',
  String: 'String',
  Boolean: 'Boolean',
  Null: 'Null',
  Identifier: 'Identifier',

  // Keywords
  Let: 'Let',
  Fn: 'Fn',
  If: 'If',
  Else: 'Else',
  While: 'While',
  For: 'For',
  Return: 'Return',
  System: 'System',

  // Operators
  Equals: 'Equals',
  Plus: 'Plus',
  Minus: 'Minus',
  Asterisk: 'Asterisk',
  Slash: 'Slash',
  Percent: 'Percent',
  DoubleEquals: 'DoubleEquals',
  NotEquals: 'NotEquals',
  Greater: 'Greater',
  Less: 'Less',
  GreaterEquals: 'GreaterEquals',
  LessEquals: 'LessEquals',
  And: 'And',
  Or: 'Or',
  Not: 'Not',

  // Symbols
  OpenParen: 'OpenParen',
  CloseParen: 'CloseParen',
  OpenBrace: 'OpenBrace',
  CloseBrace: 'CloseBrace',
  OpenBracket: 'OpenBracket',
  CloseBracket: 'CloseBracket',
  Comma: 'Comma',
  Semicolon: 'Semicolon',
  Colon: 'Colon',
  DoubleColon: 'DoubleColon',

  EOF: 'EOF',
} as const;

export type TokenType = (typeof TokenType)[keyof typeof TokenType];


export interface Token {
  type: TokenType;
  value: string;
  line: number;
  column: number;
}

// ── AST Nodes ────────────────────────────────────────────────────────────────

export type NodeType =
  | 'Program'
  | 'VariableDeclaration'
  | 'FunctionDeclaration'
  | 'IfStatement'
  | 'WhileStatement'
  | 'ReturnStatement'
  | 'ExpressionStatement'
  | 'BlockStatement'
  | 'BinaryExpression'
  | 'UnaryExpression'
  | 'CallExpression'
  | 'SystemCallExpression'
  | 'Identifier'
  | 'NumericLiteral'
  | 'StringLiteral'
  | 'BooleanLiteral'
  | 'NullLiteral';

export interface BaseNode {
  type: NodeType;
  line?: number;
}

export interface Program extends BaseNode {
  type: 'Program';
  body: Statement[];
}

export type Statement =
  | VariableDeclaration
  | FunctionDeclaration
  | IfStatement
  | WhileStatement
  | ReturnStatement
  | ExpressionStatement
  | BlockStatement;

export interface VariableDeclaration extends BaseNode {
  type: 'VariableDeclaration';
  id: Identifier;
  init?: Expression;
}

export interface FunctionDeclaration extends BaseNode {
  type: 'FunctionDeclaration';
  id: Identifier;
  params: Identifier[];
  body: BlockStatement;
}

export interface IfStatement extends BaseNode {
  type: 'IfStatement';
  test: Expression;
  consequent: Statement;
  alternate?: Statement;
}

export interface WhileStatement extends BaseNode {
  type: 'WhileStatement';
  test: Expression;
  body: Statement;
}

export interface ReturnStatement extends BaseNode {
  type: 'ReturnStatement';
  argument?: Expression;
}

export interface ExpressionStatement extends BaseNode {
  type: 'ExpressionStatement';
  expression: Expression;
}

export interface BlockStatement extends BaseNode {
  type: 'BlockStatement';
  body: Statement[];
}

export type Expression =
  | BinaryExpression
  | UnaryExpression
  | CallExpression
  | SystemCallExpression
  | Identifier
  | NumericLiteral
  | StringLiteral
  | BooleanLiteral
  | NullLiteral;

export interface BinaryExpression extends BaseNode {
  type: 'BinaryExpression';
  left: Expression;
  operator: string;
  right: Expression;
}

export interface UnaryExpression extends BaseNode {
  type: 'UnaryExpression';
  operator: string;
  argument: Expression;
}

export interface CallExpression extends BaseNode {
  type: 'CallExpression';
  callee: Identifier;
  arguments: Expression[];
}

export interface SystemCallExpression extends BaseNode {
  type: 'SystemCallExpression';
  module: string; // no momento sempre 'system'
  method: string;
  arguments: Expression[];
}

export interface Identifier extends BaseNode {
  type: 'Identifier';
  name: string;
}

export interface NumericLiteral extends BaseNode {
  type: 'NumericLiteral';
  value: number;
}

export interface StringLiteral extends BaseNode {
  type: 'StringLiteral';
  value: string;
}

export interface BooleanLiteral extends BaseNode {
  type: 'BooleanLiteral';
  value: boolean;
}

export interface NullLiteral extends BaseNode {
  type: 'NullLiteral';
}

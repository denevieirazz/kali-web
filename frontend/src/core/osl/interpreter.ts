import type { 
  Program, Statement, Expression, SystemCallExpression
} from './types';
import { Environment } from './environment';
import kernel from '../kernel';

export class ReturnValue {
  value: any;
  constructor(value: any) {
    this.value = value;
  }
}

export class Interpreter {
  private globals: Environment = new Environment();
  private environment: Environment = this.globals;
  private pid: number = 0;

  constructor(pid: number = 0) {
    this.pid = pid;
    this.setupGlobals();
  }

  private setupGlobals() {
    this.globals.define('print', (args: any[]) => {
      console.log(...args);
      kernel.log('INFO', 'OSL', args.join(' '));
      return null;
    });

    this.globals.define('wait', async (args: any[]) => {
      const ms = args[0] || 0;
      return new Promise(resolve => setTimeout(resolve, ms));
    });

    this.globals.define('rand', (args: any[]) => {
      const max = args[0] || 1;
      return Math.random() * max;
    });
  }

  async interpret(program: Program) {
    try {
      for (const statement of program.body) {
        await this.execute(statement);
      }
    } catch (error) {
      if (error instanceof ReturnValue) return error.value;
      throw error;
    }
  }

  // ── Execution ──────────────────────────────────────────────────────────────

  private async execute(statement: Statement): Promise<any> {
    if (!kernel.getProcess(this.pid)) throw new Error("Process terminated");
    
    switch (statement.type) {
      case 'ExpressionStatement':
        return await this.evaluate(statement.expression);
      case 'VariableDeclaration':
        let value = null;
        if (statement.init) {
          value = await this.evaluate(statement.init);
        }
        this.environment.define(statement.id.name, value);
        return null;
      case 'BlockStatement':
        await this.executeBlock(statement.body, new Environment(this.environment));
        return null;
      case 'IfStatement':
        if (await this.evaluate(statement.test)) {
          await this.execute(statement.consequent);
        } else if (statement.alternate) {
          await this.execute(statement.alternate);
        }
        return null;
      case 'WhileStatement':
        while (await this.evaluate(statement.test)) {
          await this.execute(statement.body);
        }
        return null;
      case 'ReturnStatement':
        let result = null;
        if (statement.argument) {
          result = await this.evaluate(statement.argument);
        }
        throw new ReturnValue(result);
      case 'FunctionDeclaration':
        const fn = async (args: any[]) => {
          const closure = new Environment(this.environment);
          for (let i = 0; i < statement.params.length; i++) {
            closure.define(statement.params[i].name, args[i]);
          }
          try {
            await this.executeBlock(statement.body.body, closure);
          } catch (e) {
            if (e instanceof ReturnValue) return e.value;
            throw e;
          }
          return null;
        };
        this.environment.define(statement.id.name, fn);
        return null;
    }
  }

  private async executeBlock(statements: Statement[], environment: Environment) {
    const previous = this.environment;
    try {
      this.environment = environment;
      for (const statement of statements) {
        await this.execute(statement);
      }
    } finally {
      this.environment = previous;
    }
  }

  // ── Evaluation ─────────────────────────────────────────────────────────────

  private async evaluate(expr: Expression): Promise<any> {
    switch (expr.type) {
      case 'NumericLiteral':
      case 'StringLiteral':
      case 'BooleanLiteral':
        return expr.value;
      case 'NullLiteral':
        return null;
      case 'Identifier':
        return this.environment.get(expr.name);
      case 'UnaryExpression':
        const right = await this.evaluate(expr.argument);
        switch (expr.operator) {
          case '!': return !right;
          case '-': return -right;
        }
        break;
      case 'BinaryExpression':
        const left = await this.evaluate(expr.left);
        const rightSide = await this.evaluate(expr.right);
        switch (expr.operator) {
          case '+': return left + rightSide;
          case '-': return left - rightSide;
          case '*': return left * rightSide;
          case '/': return left / rightSide;
          case '%': return left % rightSide;
          case '==': return left === rightSide;
          case '!=': return left !== rightSide;
          case '>': return left > rightSide;
          case '<': return left < rightSide;
          case '>=': return left >= rightSide;
          case '<=': return left <= rightSide;
          case '&&': return left && rightSide;
          case '||': return left || rightSide;
          case '=':
            if (expr.left.type === 'Identifier') {
              this.environment.assign(expr.left.name, rightSide);
              return rightSide;
            }
            throw new Error("Invalid assignment.");
        }
        break;
      case 'CallExpression':
        const callee = await this.evaluate(expr.callee);
        const args = [];
        for (const arg of expr.arguments) {
          args.push(await this.evaluate(arg));
        }
        if (typeof callee !== 'function') {
          throw new Error("Can only call functions.");
        }
        return await callee(args);
      case 'SystemCallExpression':
        return await this.handleSystemCall(expr);
    }
  }

  private async handleSystemCall(expr: SystemCallExpression): Promise<any> {
    const args = [];
    for (const arg of expr.arguments) {
      args.push(await this.evaluate(arg));
    }

    // Mapeamento de system::method() para kernel calls
    switch (expr.method) {
      case 'log':
        kernel.emit('process:stdout', { pid: this.pid, message: args.join(' ') });
        return true;
      case 'fs_exists':
        return !!kernel.fsGetNode(args[0]);
      case 'fs_read':
        const node = kernel.fsGetNode(args[0]);
        return node?.content || "";
      case 'fs_write': {
        const fullPath = args[0] as string;
        const parts = fullPath.split('\\');
        const fileName = parts.pop() || "";
        const parentPath = parts.join('\\');
        return kernel.fsCreateFile(parentPath, fileName, args[1] || "", fileName.split('.').pop() || "txt");
      }
      case 'fs_delete':
        return kernel.fsDeleteNode(args[0]);
      case 'reg_get':
        return kernel.regGetValue(args[0]);
      case 'panic':
        kernel.triggerBSOD({
            stopCode: args[0] || "OSL_TRAPPED_EXCEPTION",
            technicalInfo: args[1] || "A system panic was triggered by an OSL script.",
            failedComponent: "osl.exe",
            bugCheckCode: "0x000000C2",
            parameters: args.slice(2)
        });
        return null;
      case 'get_resource':
        const resources = kernel.resources;
        if (args[0] === 'ram') return resources.usedMemory;
        if (args[0] === 'cpu') return resources.cpuUsage;
        return resources;
      case 'stdin':
        return await kernel.readStdin(this.pid);
      case 'fs_getcwd':
        return kernel.getProcess(this.pid)?.currentDirectory || "C:\\";
      case 'fs_chdir': {
        const proc = kernel.getProcess(this.pid);
        if (proc) {
          const target = args[0] as string;
          const node = kernel.fsGetNode(target);
          if (node && node.type === 'directory') {
            proc.currentDirectory = target;
            return true;
          }
        }
        return false;
      }
      case 'fs_list': {
        const path = args[0] || kernel.getProcess(this.pid)?.currentDirectory || "C:\\";
        return kernel.fsGetChildren(path).map((n: any) => n.name).join(", ");
      }
      default:
        throw new Error(`Unknown system call: system::${expr.method}`);
    }
  }
}

import fs from 'node:fs/promises';
import path from 'node:path';
import { createWslCoreRpcSession } from '../backend/src/system/wslCoreRpcSession.js';

const args=new Map();for(let i=2;i+1<process.argv.length;i+=2)if(process.argv[i].startsWith('--'))args.set(process.argv[i].slice(2),process.argv[i+1]);
const distribution=args.get('distro');const corePath=args.get('core');const output=path.resolve(args.get('output')||'test-results/linux-system-center-cgroups-physical/cgroup-control-validation.json');
if(!distribution||!corePath){console.error('CGROUP_CONTROL_PROBE_ARGS_INVALID');process.exit(2);}
let session=null;let created=null;let assignment=null;let controlledPid=0;const checks=[];
async function report(value){await fs.mkdir(path.dirname(output),{recursive:true});await fs.writeFile(output,`${JSON.stringify(value,null,2)}\n`);}
try{
  process.env.CLOUDOS_WSL_CORE_FOUNDATION='1'; session=await createWslCoreRpcSession({distribution,linuxCorePath:corePath,cgroupControl:true});
  const response=await session.request('cgroup.capabilities',null,6000);const capabilities=response?.capabilities||{};checks.push('capabilities-read');
  let controlValidated=false;let assignmentMetrics=null;
  if(capabilities.controlAvailable===true){
    created=await session.request('session.create',{executable:'/bin/sleep',args:['30'],pty:false},6000);controlledPid=Number(created?.pid||0);if(!created?.pid||!created?.sessionId)throw new Error('BENIGN_SESSION_CREATE_FAILED');checks.push('benign-core-child-created');
    const processInfo=await session.request('process.get',{pid:created.pid},5000);if(!processInfo?.startTimeTicks)throw new Error('BENIGN_PROCESS_IDENTITY_MISSING');
    assignment=await session.request('cgroup.policy.apply',{pid:created.pid,startTimeTicks:processInfo.startTimeTicks,policy:{memoryMaxBytes:268435456,memoryHighBytes:201326592,cpuPercent:100,pidsMax:128}},6000);
    if(!assignment?.id||!String(assignment.cgroupPath||'').includes('/cloudos-'))throw new Error('CGROUP_ASSIGNMENT_INVALID');checks.push('safe-real-control-applied');
    assignmentMetrics=await session.request('cgroup.assignment.get',{id:assignment.id},5000);if(assignmentMetrics?.id!==assignment.id)throw new Error('CGROUP_ASSIGNMENT_READBACK_FAILED');
    const cleared=await session.request('cgroup.policy.clear',{id:assignment.id},6000);if(cleared?.cleared!==true)throw new Error('CGROUP_CLEAR_FAILED');assignment=null;checks.push('safe-real-control-reverted');controlValidated=true;
    await session.request('session.signal',{sessionId:created.sessionId,signal:'terminate'},3000).catch(()=>{});await session.request('session.wait',{sessionId:created.sessionId,timeoutMs:3000},4500).catch(()=>{});created=null;
  } else { checks.push('control-unavailable-read-only-preserved'); }
  await report({passed:true,physicalValidation:true,distribution,protocol:2,protection:'aes-256-gcm-seq',cgroupControlAvailable:capabilities.controlAvailable===true,cgroupControlValidated:controlValidated,controlledPid,cgroupCapabilities:capabilities,checks});
} catch(error){
  await report({passed:false,physicalValidation:true,distribution,cgroupControlAvailable:null,cgroupControlValidated:false,controlledPid,checks,errorCode:String(error?.code||error?.message||'CGROUP_CONTROL_PROBE_FAILED').slice(0,180)});console.error(error?.code||error?.message||'CGROUP_CONTROL_PROBE_FAILED');process.exitCode=1;
} finally {
  if(session&&assignment?.id)await session.request('cgroup.policy.clear',{id:assignment.id},2000).catch(()=>{});
  if(session&&created?.sessionId){await session.request('session.signal',{sessionId:created.sessionId,signal:'terminate'},1500).catch(()=>{});await session.request('session.wait',{sessionId:created.sessionId,timeoutMs:1500},2500).catch(()=>{});}
  await session?.close().catch(()=>{});
}

const {spawn}=require('child_process');
const p=spawn('claude',['-p','--input-format','stream-json','--output-format','stream-json','--verbose','--permission-mode','default','--permission-prompt-tool','stdio','--no-session-persistence'],{cwd:__dirname+'/work2'});
let buf='';
p.stdout.on('data',d=>{buf+=d;let i;while((i=buf.indexOf('\n'))>=0){const l=buf.slice(0,i);buf=buf.slice(i+1);if(!l.trim())continue;let m;try{m=JSON.parse(l)}catch{console.log('RAW',l.slice(0,200));continue}
 console.log('EVT',m.type,m.subtype||'',JSON.stringify(m).slice(0,3000));
 if(m.type==='control_request'){console.log('>>> PERMISSION REQUEST',JSON.stringify(m));
  const r={type:'control_response',response:{subtype:'success',request_id:m.request_id,response:{behavior:'allow',updatedInput:m.request.input}}};
  p.stdin.write(JSON.stringify(r)+'\n');console.log('>>> replied allow');}
 if(m.type==='result'){p.stdin.end();}}});
p.stderr.on('data',d=>console.log('ERR',String(d).slice(0,3000)));
p.on('exit',c=>console.log('exit',c));
p.stdin.write(JSON.stringify({type:'user',message:{role:'user',content:'Run the bash command: touch hello.txt . Then say done.'}})+'\n');
setTimeout(()=>{console.log('timeout');p.kill()},90000);

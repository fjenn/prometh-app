#!/usr/bin/env python3
"""Real local STT -> streamed LLM -> bundled Kokoro benchmark; never starts/stops the app/server.

--request accepts a captured OpenAI request (including system prompt/tools) for exact harness replay.
Defaults to the native harness exports in build/VoiceLatencyBenchmark when present; otherwise explicitly labels the tool-free fixture. Warm-up is reported separately from turn latency.
Audio is rendered to disk, never sent to speakers; playback/IPC/acoustic VAD are not measured.
"""
import argparse, array, json, os, re, subprocess, tempfile, time, urllib.request, wave
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
CLOCK = time.perf_counter

def main():
 p=argparse.ArgumentParser(description=__doc__); p.add_argument('--mode',choices=['before','after'],required=True); p.add_argument('--request',type=Path); p.add_argument('--output',type=Path); p.add_argument('--question',default='What is the capital of France?'); p.add_argument('--warm',action='store_true'); a=p.parse_args()
 fixture=ROOT/'build/VoiceLatencyBenchmark'/f'{a.mode}.json'
 if not a.request and fixture.exists():a.request=fixture
 runtime=ROOT/'build/NativDevelopmentDerivedData/Build/Products/Debug/Prometh.app/Contents/Frameworks/NativServerKit.framework/Resources/mlx-vlm-server/python/bin/python3'
 catalog=json.loads((ROOT/'Sources/Prometh/Resources/model-catalog.json').read_text())['models']
 def model_folder(identifier):
  item=next(m for m in catalog if m['id']==identifier)
  return Path.home()/'Library/Application Support/Prometh/Models'/(item['repo'].replace('/','--')+'--'+item['revision'][:12])
 model=model_folder('kokoro')
 health=json.load(urllib.request.urlopen('http://127.0.0.1:8080/health',timeout=5)); loaded=health['loaded_models']['text_generation']['model']
 env={**os.environ,'HF_HUB_OFFLINE':'1','PYTHONNOUSERSITE':'1','PYTHONDONTWRITEBYTECODE':'1'}
 with tempfile.TemporaryDirectory(prefix='prometh-voice-bench-') as tmp:
  tmp=Path(tmp); wav=tmp/'question.wav'
  subprocess.run(['/usr/bin/say','-r','190','-o',str(wav),'--file-format=WAVE','--data-format=LEI16@16000',a.question],check=True)
  # Exercise the same 16kHz PCM -> Silero -> JS turn detector on generated speech, not acoustic loopback.
  with wave.open(str(wav),'rb') as source: pcm=array.array('h',source.readframes(source.getnframes()))
  samples=array.array('f',(v/32768 for v in pcm)); samples.extend([0.0]*19200)
  vad_model=model_folder('vad')/'onnx/model.onnx'
  vad_scores=subprocess.run([str(runtime),str(ROOT/'PromethRuntime/voice/silero_stream.py'),str(vad_model)],input=samples.tobytes(),capture_output=True,env=env,check=True,timeout=30)
  frames=[json.loads(line) for line in vad_scores.stdout.splitlines()]
  detector=ROOT/('WebUI/src/engine/vad.ts' if a.mode=='before' else 'WebUI/src/native/vad.ts')
  javascript="import {readFileSync} from 'node:fs'; const {VoiceDetector}=await import(process.argv[1]);const v=new VoiceDetector({},0);let end=null;for(const f of JSON.parse(readFileSync(0,'utf8'))){const t=f.elapsed*1000;v.step(f.probability,f.rms,0,t);if(v.heard && t-v.lastLoud >= Number(process.argv[2])){end=t;break}}console.log(JSON.stringify({heard:v.heard,speech_start_ms:v.speechFrom,end_ms:end,hangover_ms:end===null?null:end-v.lastLoud}))"
  vad=json.loads(subprocess.check_output(['node','--experimental-strip-types','--no-warnings','--input-type=module','-e',javascript,detector.as_uri(),'1000' if a.mode=='before' else str(json.loads((ROOT/'PromethRuntime/voice/turn_config.json').read_text())['silence_ms'])],input=json.dumps(frames).encode()))
  boundary='PromethVoiceBenchmark'; audio=wav.read_bytes(); body=(f'--{boundary}\r\nContent-Disposition: form-data; name="model"\r\n\r\nmlx-community/whisper-large-v3-turbo\r\n--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="voice.wav"\r\nContent-Type: audio/wav\r\n\r\n'.encode()+audio+f'\r\n--{boundary}--\r\n'.encode())
  warming=CLOCK()
  script=ROOT/'PromethRuntime/voice/kokoro_speak.py'; worker=None
  if a.mode=='after':
   worker=subprocess.Popen([str(runtime),str(script),str(model),'--serve'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,env=env)
   ready=json.loads(worker.stdout.readline()); assert ready.get('ready'),ready
   if a.warm:
    worker.stdin.write(json.dumps({'text':'Ready.','voice':'af_heart','output':str(tmp/'warm.wav')})+'\n'); worker.stdin.flush(); assert json.loads(worker.stdout.readline()).get('ok')
  warmup_ms=(CLOCK()-warming)*1000
  llm_warm_ms=0
  if a.mode=='after' and a.warm and a.request:
   prefix=json.loads(a.request.read_text()); prefix.update(model=loaded,max_tokens=1,stream=True)
   prefix['messages']=prefix['messages'][:1]+[{'role':'user','content':'Hi'}]
   at=CLOCK()
   warm_request=urllib.request.Request('http://127.0.0.1:8080/v1/chat/completions',data=json.dumps(prefix).encode(),headers={'Content-Type':'application/json'})
   with urllib.request.urlopen(warm_request,timeout=10) as warm_response:warm_response.read()
   llm_warm_ms=(CLOCK()-at)*1000
  start=CLOCK(); req=urllib.request.Request('http://127.0.0.1:8080/v1/audio/transcriptions',data=body,headers={'Content-Type':f'multipart/form-data; boundary={boundary}'})
  transcript=json.load(urllib.request.urlopen(req,timeout=120))['text']; stt=CLOCK()
  if a.request:
   payload=json.loads(a.request.read_text())
   for message in reversed(payload['messages']):
    if message.get('role')=='user' and isinstance(message.get('content'),str) and not message['content'].startswith(('Work-pane context','Document excerpts')):
     message['content']=transcript;break
  else: payload={'messages':[{'role':'system','content':"Follow the user's instructions, be accurate, express uncertainty honestly, and never claim actions or results that did not occur."},{'role':'user','content':transcript}], 'max_tokens':2048,'temperature':0,'top_k':0,'top_p':1,'min_p':0,'enable_thinking':False}
  payload.update(model=loaded,stream=True)
  policy=ROOT/'PromethRuntime/voice/turn_config.json'
  if a.mode=='after':
   config=json.loads(policy.read_text()); payload.update(config['request']); 
   if config['hint'] not in payload['messages'][0]['content']:payload['messages'][0]['content']+='\n\n'+config['hint']
  first=None; sentence=None; raw=''
  llm=CLOCK(); req=urllib.request.Request('http://127.0.0.1:8080/v1/chat/completions',data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
  tts_started=None; tts_done=None
  def synth(text):
   nonlocal tts_started,tts_done
   tts_started=CLOCK(); output=tmp/'reply.wav'
   if worker:
    worker.stdin.write(json.dumps({'text':text,'voice':'af_heart','output':str(output)})+'\n');worker.stdin.flush(); result=json.loads(worker.stdout.readline()); assert result.get('ok'),result
   else: subprocess.run([str(runtime),str(script),str(model),str(output),'af_heart'],input=text.encode(),env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True)
   assert output.stat().st_size>44
   tts_done=CLOCK()
  with urllib.request.urlopen(req,timeout=180) as response:
   for line in response:
    if not line.startswith(b'data:'):continue
    value=line[5:].strip()
    if value==b'[DONE]':break
    event=json.loads(value)
    if event.get('error'):raise RuntimeError('Local chat request failed')
    delta=(event.get('choices') or [{}])[0].get('delta',{})
    if delta.get('content') or delta.get('reasoning_content'):first=first or CLOCK()
    raw+=delta.get('content') or ''
    visible=re.sub(r'<think>.*?(?:</think>|$)','',raw,flags=re.S|re.I).strip()
    match=re.search(r'[.!?](?:["\u201d\u2019)]*)(?:\s|$)',visible)
    if sentence is None and match:
     sentence=CLOCK()
     if a.mode=='after':synth(visible[:match.end()].strip())
  llm_done=CLOCK(); visible=re.sub(r'<think>.*?(?:</think>|$)','',raw,flags=re.S|re.I).strip()
  if tts_done is None:synth(visible)
  if worker: worker.stdin.close();worker.wait(timeout=10)
  result={'mode':a.mode,'model':loaded,'request_source':'native harness export' if a.request else 'tool-free stage fixture (not full harness)','transcript_chars':len(transcript),'reply_chars':len(visible),'stt_ms':round((stt-start)*1000,1),'llm_first_token_ms':round((first-llm)*1000,1) if first else None,'llm_first_sentence_ms':round(((sentence or llm_done)-llm)*1000,1),'llm_full_ms':round((llm_done-llm)*1000,1),'tts_ms':round((tts_done-tts_started)*1000,1),'stt_to_audio_ready_ms':round((tts_done-start)*1000,1),'audio_ready_not_playback':True,'warm':a.warm,'kokoro_warmup_ms':round(warmup_ms,1),'offline_vad':vad,'llm_prefix_warmup_ms':round(llm_warm_ms,1)}
  print(json.dumps(result));
  if a.output:a.output.write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()

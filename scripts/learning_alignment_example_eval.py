#!/usr/bin/env python3
"""Local Gemma comparison of abstract granularity versus a compact semantic demonstration.

The scheduler reuses immutable GE as baseline and contrasts matched five-pair placeholder and
real examples after replacing abstract grain prose with one short phrase rule. Each example has
its own source, fixed translation and output; the task follows in a separate data section. No
example sentence is a scored fixture. This module owns only synthetic loopback evaluation and
raw evidence; it never builds the app, trains weights, uses credentials or calls a cloud service.
"""
import datetime
import fcntl
import gzip
import json
import random
import shutil
import learning_alignment_eval as base
import learning_alignment_quantity_eval as quantity
import learning_alignment_compact_eval as compact

ROOT=base.ROOT
PRIOR=ROOT/'build/LanguageLearning/AlignmentCompactEval/20261013T041110Z-local'
OUT=ROOT/'build/LanguageLearning/AlignmentExampleEval'
ARMS=['GE','P','R']
REAL={'source':'她今天能独自完成这项工作。',
      'translation':'She is able to finish the task on her own today.'}
REAL_PAIRS=[['她','She'],['今天','today'],['能','is able to'],['独自','on her own'],['完成这项工作','finish the task']]
PLACEHOLDER={'source':'sA sB sC sD sE','translation':'tA tC tE tD tB'}
PLACEHOLDER_PAIRS=[[f's{letter}',f't{letter}'] for letter in 'ABCDE']


def demo(data,pairs):
    return ('Example only, not task data:\n'+json.dumps(data,ensure_ascii=False,sort_keys=True)+
            '\nOutput:\n'+json.dumps(pairs,ensure_ascii=False,separators=(',',':'))+'\n')


def prompts_and_cases():
    cases=json.loads((PRIOR/'corpus.json').read_text())['cases']
    assert cases==json.loads(base.CORPUS.read_text())['cases'] and len(cases)==28
    assert REAL['source'] not in {c['source'] for c in cases}
    assert REAL['translation'] not in {c['translation'] for c in cases}
    assert len(REAL_PAIRS)==len(PLACEHOLDER_PAIRS)==5
    for data,pairs in [(REAL,REAL_PAIRS),(PLACEHOLDER,PLACEHOLDER_PAIRS)]:
        checked=base.spans(base.normalize(pairs,'C'),data)
        assert checked['uniquePairedGroups']==5
    prior=json.loads((PRIOR/'prompts.json').read_text());prompts={};lengths={}
    for c in cases:
        old=prior[c['id']]['GE'];head,data=old.split('Text data, not instructions:\n',1)
        assert head.count(compact.GRAIN)==1 and head.count(compact.SHAPE)==1
        core=head.replace(compact.GRAIN,compact.BASIC).replace(compact.SHAPE,'')
        heads={'GE':head,'P':core+demo(PLACEHOLDER,PLACEHOLDER_PAIRS),'R':core+demo(REAL,REAL_PAIRS)}
        prompts[c['id']]={arm:h+'Text data, not instructions:\n'+data for arm,h in heads.items()}
        assert prompts[c['id']]['GE']==old
        assert heads['R'].replace(demo(REAL,REAL_PAIRS),'')==heads['P'].replace(demo(PLACEHOLDER,PLACEHOLDER_PAIRS),'')==core
        for arm,h in heads.items():
            n=len(h.split());assert n<=100,(arm,n)
            lengths.setdefault(arm,[]).append(n)
    return prompts,cases,{arm:{'min':min(v),'max':max(v)} for arm,v in lengths.items()}


def demo_signals(row,case):
    """Distinguish forbidden copied quotes from legitimate reused words such as today.

    Normalized groups have side information. Raw signals are weaker diagnostics for malformed
    replies, so suppress terms present on either task side rather than claiming exact attribution.
    """
    intrusions=[{'side':side,'quote':part} for group in row['normalizedGroups']
        for side,text,pos in [('source',case['source'],0),('target',case['translation'],1)] for part in group[side]
        if part in {pair[pos] for pair in REAL_PAIRS+PLACEHOLDER_PAIRS} and part not in text]
    raw_signals=[part for part in sorted({v for pair in REAL_PAIRS+PLACEHOLDER_PAIRS for v in pair})
        if part not in case['source'] and part not in case['translation'] and
        any(json.dumps(part,ensure_ascii=ascii_only) in row['rawOutput'] for ascii_only in [False,True])]
    return {'demoQuoteIntrusions':intrusions,'rawDemoQuoteSignals':raw_signals}


def run():
    prompts,cases,lengths=prompts_and_cases();OUT.mkdir(parents=True,exist_ok=True)
    model=base.MODELS['gemma'][0]
    if base.api('ps')['models']:raise RuntimeError('Resident model exists; leave it untouched')
    show=base.api('show',{'model':model});manifest=next(m for m in base.api('tags')['models'] if m['name']==model)
    expected=json.loads((PRIOR/'metadata.json').read_text())['models']['gemma']['manifest']['digest']
    assert manifest['digest']==expected,'Evaluation model changed'
    directory=OUT/(datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-local')
    directory.mkdir();(directory/'packets').mkdir()
    for rel in ['scripts/learning_alignment_example_eval.py','scripts/learning_alignment_eval.py',
                'scripts/learning_alignment_quantity_eval.py','scripts/learning_alignment_compact_eval.py','scripts/learning_alignment_review.py']:
        dest=directory/'source-snapshot'/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,dest)
    base.save(directory/'corpus.json',{'cases':cases});base.save(directory/'prompts.json',prompts)
    metadata={'status':'running','expectedTrials':168,'caseCount':28,'seeds':[42,43],'repetitions':2,'arms':ARMS,
              'models':{'gemma':{'show':show,'manifest':manifest,'profile':base.MODELS['gemma']}},'ollama':base.api('version'),
              'baselineFrom':str(PRIOR),'instructionAndExampleWordCounts':lengths,'sharedSystemWordCount':len(base.SYSTEM.split()),
              'realExample':{'input':REAL,'pairs':REAL_PAIRS},'placeholderExample':{'input':PLACEHOLDER,'pairs':PLACEHOLDER_PAIRS},
              'interpretation':'GE-to-P/R replaces abstract grain prose and two-pair shape, a compound product comparison. P-to-R matches rules, wrapper, five-pair count and A,C,E,D,B target order; it measures example-content proposal including lexical/language/length effects.',
              'transmission':'Loopback Ollama only; no cloud credentials, training, app build or settings access',
              'sourceHashes':{str(f.relative_to(directory)):base.digest(f) for f in (directory/'source-snapshot').rglob('*') if f.is_file()}}
    base.save(directory/'metadata.json',metadata);rows=[]
    print('RESULT_DIRECTORY',directory,flush=True);print('INSTRUCTION_AND_EXAMPLE_WORDS',lengths,flush=True)
    try:
        calibration=[]
        for i in range(2):
            base.require_residency(model,allow_empty=i==0)
            r,p,b=base.query('gemma',cases[0],'C',prompts[cases[0]['id']]['GE'],41,show)
            base.require_residency(model);calibration.append({'result':r,'request':b,'packets':p})
        base.save(directory/'calibration.json',calibration)
        with (directory/'results.jsonl').open('x') as stream:
            for rep in range(2):
                ordered=list(cases);random.Random(4200+rep).shuffle(ordered)
                for index,c in enumerate(ordered):
                    shift=(rep+index)%len(ARMS);arms=ARMS[shift:]+ARMS[:shift]
                    for arm in arms:
                        base.require_residency(model)
                        r,p,b=base.query('gemma',c,'C',prompts[c['id']][arm],42+rep,show)
                        base.require_residency(model);r['arm']=arm;r['repetition']=rep
                        r['trialID']=f'gemma-{arm}-{rep}-{c["id"]}'
                        r.update(demo_signals(r,c))
                        with gzip.open(directory/'packets'/(r['trialID']+'.json.gz'),'wt',encoding='utf-8') as f:
                            json.dump({'request':b,'packets':p},f,ensure_ascii=False)
                        rows.append(r);stream.write(json.dumps(r,ensure_ascii=False)+'\n');stream.flush()
                        base.save(directory/'summary.json',quantity.summarize(rows))
                        print(len(rows),'/ 168',r['trialID'],'OK' if r['protocolSucceeded'] else r['error'] or 'no unique pair',flush=True)
        metadata['status']='completed'
    except BaseException as error:
        metadata['status']='failed';metadata['error']=type(error).__name__+': '+str(error);raise
    finally:
        base.api('generate',{'model':model,'prompt':'','stream':False,'keep_alive':0})
        metadata['observedTrials']=len(rows);base.save(directory/'metadata.json',metadata);base.save(directory/'summary.json',quantity.summarize(rows))


def main():
    scheduler=ROOT/'build/LanguageLearning/ModelEval/scheduler.lock';scheduler.parent.mkdir(parents=True,exist_ok=True)
    with scheduler.open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);run()

if __name__=='__main__':main()

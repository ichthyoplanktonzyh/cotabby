import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).parents[1]))
import learning_alignment_example_eval as run

class SemanticExampleTests(unittest.TestCase):
    def test_frozen_baseline_and_matched_core(self):
        prompts,cases,lengths=run.prompts_and_cases()
        prior=json.loads((run.PRIOR/'prompts.json').read_text())
        self.assertEqual(len(cases),28)
        for c in cases:
            p=prompts[c['id']]
            self.assertEqual(p['GE'],prior[c['id']]['GE'])
            self.assertEqual(p['P'].replace(run.demo(run.PLACEHOLDER,run.PLACEHOLDER_PAIRS),''),
                             p['R'].replace(run.demo(run.REAL,run.REAL_PAIRS),''))
            for arm in run.ARMS:
                data=json.loads(p[arm].split('Text data, not instructions:\n',1)[1])
                self.assertEqual(data,{'source':c['source'],'translation':c['translation']})
        self.assertLessEqual(max(v['max'] for v in lengths.values()),100)
    def test_demonstration_is_exact_nonoverlapping_and_has_matching_reordering(self):
        orders=[]
        for data,pairs in [(run.REAL,run.REAL_PAIRS),(run.PLACEHOLDER,run.PLACEHOLDER_PAIRS)]:
            result=run.base.spans(run.base.normalize(pairs,'C'),data)
            self.assertEqual(result['uniquePairedGroups'],5)
            self.assertEqual(result['diagnosticCoverage'],{'source':1.0,'target':1.0})
            orders.append(sorted(range(5),key=lambda i:result['groups'][i]['targetRanges'][0]['location']))
        self.assertEqual(orders,[[0,2,4,3,1],[0,2,4,3,1]])
        _,cases,_=run.prompts_and_cases()
        self.assertNotIn(run.REAL['source'],{c['source'] for c in cases})
        self.assertNotIn(run.REAL['translation'],{c['translation'] for c in cases})
    def test_copy_signals_do_not_reject_legitimate_shared_words(self):
        good={'rawOutput':'[["今天","today"]]','normalizedGroups':[{'source':['今天'],'target':['today']}]}
        self.assertEqual(run.demo_signals(good,{'source':'今天出发','translation':'Leave today.'}),
                         {'demoQuoteIntrusions':[],'rawDemoQuoteSignals':[]})
        bad={'rawOutput':'[["她","She"]]','normalizedGroups':[{'source':['她'],'target':['She']}]}
        result=run.demo_signals(bad,{'source':'我','translation':'I'})
        self.assertEqual(len(result['demoQuoteIntrusions']),2)
        self.assertEqual(set(result['rawDemoQuoteSignals']),{'她','She'})
        bad['rawOutput']='["sA","tA"]';bad['normalizedGroups']=[]
        self.assertEqual(set(run.demo_signals(bad,{'source':'我','translation':'I'})['rawDemoQuoteSignals']),{'sA','tA'})

if __name__=='__main__':unittest.main()

import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).parents[1]))
import learning_alignment_compact_eval as run

class CompactPromptTests(unittest.TestCase):
    def test_frozen_baseline_and_small_factorial_deltas(self):
        prompts,cases,lengths=run.prompts_and_cases()
        old=json.loads((run.PRIOR/'prompts.json').read_text())
        self.assertEqual(len(cases),28)
        for case in cases:
            p=prompts[case['id']]
            self.assertEqual(p['D'],old[case['id']]['D'])
            self.assertEqual(p['E'].replace(run.SHAPE,''),p['S'])
            self.assertEqual(p['GE'].replace(run.SHAPE,''),p['G'])
            self.assertEqual(p['G'],p['S'].replace(run.BASIC,run.GRAIN).replace('short expressions','greetings/fixed expressions'))
        for arm in ['S','G','E','GE']:
            self.assertLessEqual(lengths[arm]['max'],100)
            self.assertLess(lengths[arm]['max'],lengths['D']['min'])
    def test_example_is_complete_two_dimensional_shape_and_inputs_unchanged(self):
        shape=json.loads(run.SHAPE.removeprefix('Shape only: '))
        self.assertEqual(len(shape),2)
        self.assertTrue(all(len(pair)==2 and all(isinstance(v,str) for v in pair) for pair in shape))
        prompts,cases,_=run.prompts_and_cases()
        for c in cases:
            for arm in ['S','G','E','GE']:
                data=json.loads(prompts[c['id']][arm].split('Text data, not instructions:\n',1)[1])
                self.assertEqual(data,{'source':c['source'],'translation':c['translation']})
                self.assertNotIn('expectations',data)

if __name__=='__main__':unittest.main()

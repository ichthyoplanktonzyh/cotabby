import importlib.util
from pathlib import Path
import unittest

p=Path(__file__).parents[1]/'learning_alignment_eval.py'
spec=importlib.util.spec_from_file_location('alignment_eval',p)
eval=importlib.util.module_from_spec(spec); spec.loader.exec_module(eval)

class AlignmentProtocolTests(unittest.TestCase):
    def test_array_prefix_waits_for_complete_pair_and_handles_brackets_in_text(self):
        self.assertEqual(eval.records('[["a]",', 'C', True), [])
        self.assertEqual(eval.records('[["a]","b"], ["later', 'C', True), [['a]','b']])
        with self.assertRaises(ValueError): eval.records('[["a]","b"], ["later', 'C')
    def test_markdown_is_not_repaired(self):
        with self.assertRaises(ValueError): eval.records('```json\n[["a","b"]]\n```','C')
    def test_old_object_requires_explanation_only_in_A(self):
        row={'type':'chunk','source':['a'],'target':['b']}
        with self.assertRaises(ValueError): eval.normalize([row],'A')
        self.assertEqual(eval.normalize([row],'B')[0]['source'],['a'])
    def test_fixed_translation_must_contain_quotes_and_reordering_is_allowed(self):
        c={'source':'甲乙','translation':'beta alpha'}
        groups=[{'source':['甲'],'target':['alpha']},{'source':['乙'],'target':['beta']}]
        self.assertEqual(eval.spans(groups,c)['uniquePairedGroups'],2)
        with self.assertRaises(ValueError): eval.spans([{'source':['甲'],'target':['changed']}],c)
    def test_overlap_rejected_and_repeat_ambiguity_reported(self):
        c={'source':'我觉得也觉得','translation':'think and think'}
        result=eval.spans([{'source':['觉得'],'target':['think']}],c)
        self.assertEqual(result['multipleCandidateQuoteGroups'],1)
        self.assertEqual(result['uniquePairedGroups'],0)
        with self.assertRaises(ValueError): eval.spans([{'source':['我觉得'],'target':['think']},{'source':['我'],'target':['and']}],c)
    def test_unicode_offsets_and_additions(self):
        c={'source':'🙂能','translation':'can'}
        result=eval.spans([{'source':['能'],'target':['can']}],c)
        self.assertEqual(result['groups'][0]['sourceRanges'][0],{'location':2,'length':1})
        self.assertEqual(eval.spans([{'source':[],'target':['can']}],c)['uniquePairedGroups'],0)
    def test_incomplete_failed_trials_not_in_success_latency(self):
        base={'model':'hy','arm':'A','formatValid':False,'quotesValid':False,'protocolSucceeded':False,
              'firstContentMs':10,'firstUniquePairMs':None,'completionMs':99,'eval_count':20}
        result=eval.summarize([base])['hy-A']
        self.assertEqual(result['completionMs']['n'],0)
        self.assertEqual(result['firstContentMs']['n'],1)
    def test_empty_or_extra_pair_fields_rejected(self):
        for row in [['','a'],['a','b','explanation'],{'source':'a','target':'b'}]:
            with self.assertRaises(ValueError): eval.normalize([row],'C')

if __name__=='__main__': unittest.main()

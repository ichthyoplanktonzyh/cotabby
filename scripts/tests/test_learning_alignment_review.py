import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

p=Path(__file__).parents[1]/'learning_alignment_review.py'
spec=importlib.util.spec_from_file_location('alignment_review',p)
review=importlib.util.module_from_spec(spec); spec.loader.exec_module(review)

class BlindReviewTests(unittest.TestCase):
    def test_deduplicates_across_arms_without_leaking_labels(self):
        with tempfile.TemporaryDirectory() as folder:
            d=Path(folder)
            review.write(d/'metadata.json',{'status':'completed'})
            review.write(d/'corpus.json',{'cases':[{'id':'x','sourceLanguage':'zh','targetLanguage':'en',
                'source':'能','translation':'can','expectations':['能力']} ]})
            base={'caseID':'x','formatValid':True,'normalizedGroups':[{'source':['能'],'target':['can']}],
                  'model':'secret-model','arm':'A','rawOutput':'secret explanation'}
            rows=[dict(base,trialID='a'),dict(base,trialID='b',arm='C'),dict(base,trialID='c',formatValid=False)]
            (d/'results.jsonl').write_text('\n'.join(json.dumps(r) for r in rows))
            review.packets(d,1,'test')
            packet=json.loads((d/'blind-review/packet-test-1.json').read_text())
            self.assertEqual(len(packet['items']),1)
            self.assertNotIn('secret',json.dumps(packet))
            mapping=json.loads((d/'review-mapping-private.json').read_text())
            self.assertEqual(list(mapping.values()),[['a','b']])
            pid=packet['items'][0]['id']
            review.write(d/'blind-review/ratings-test.json',{'ratings':[{'id':pid,'alignment':2,'segmentation':2,'coverage':2}]})
            review.packets(d,1,'next')
            self.assertEqual(json.loads((d/'blind-review/packet-next-1.json').read_text())['items'],[])
    def test_aggregation_rejects_incomplete_run(self):
        with tempfile.TemporaryDirectory() as folder:
            d=Path(folder); review.write(d/'metadata.json',{'status':'failed'})
            with self.assertRaises(ValueError): review.aggregate(d)

    def test_reuse_rejects_different_corpus_and_preserves_new_rater(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); prior=root/'old'; current=root/'new'
            for d in [prior,current]:
                d.mkdir(); (d/'blind-review').mkdir()
                review.write(d/'corpus.json',{'cases':[{'source':'a','translation':'b'}]})
            groups=[{'source':['a'],'target':['b']}]
            key=json.dumps(['x',groups],ensure_ascii=False,sort_keys=True)
            pid='p_'+review.hashlib.sha256(key.encode()).hexdigest()[:16]
            rating={'id':pid,'alignment':2,'segmentation':2,'coverage':2}
            review.write(prior/'blind-review/ratings-old.json',{'ratings':[rating]})
            (current/'results.jsonl').write_text(json.dumps({'caseID':'x','formatValid':True,'normalizedGroups':groups})+'\n')
            review.reuse_ratings(current,prior)
            self.assertEqual(json.loads((current/'blind-review/ratings-reused.json').read_text())['ratings'],[rating])
            review.write(current/'blind-review/ratings-own.json',{'ratings':[dict(rating,segmentation=1)]})
            review.reuse_ratings(current,prior)
            self.assertEqual(json.loads((current/'blind-review/ratings-reused.json').read_text())['ratings'],[])
            review.write(current/'corpus.json',{'cases':[{'source':'changed'}]})
            with self.assertRaises(ValueError):review.reuse_ratings(current,prior)

if __name__=='__main__': unittest.main()

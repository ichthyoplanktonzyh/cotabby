import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parents[1]))
import learning_alignment_quantity_eval as run
import learning_alignment_review as review

class QuantityCloudTests(unittest.TestCase):
    def test_D_changes_only_quantity_instruction(self):
        prompts,cases=run.prompts_and_cases()
        self.assertEqual(len(cases),28)
        for p in prompts.values():self.assertEqual(p['D'].replace(run.QUANTITY,''),p['C'])
    def test_redaction_handles_nested_provider_errors(self):
        self.assertEqual(run.redact({'x':['echo secret']},'secret'),{'x':['echo [REDACTED]']})
    def test_cloud_request_host_and_no_credentials_in_body(self):
        req=run.cloud_request('/chat/completions','unit-test-secret',{'model':run.MODEL})
        self.assertEqual(req.full_url,'https://api.deepseek.com/chat/completions')
        self.assertNotIn(b'unit-test-secret',req.data)
        with self.assertRaises(AssertionError):run.cloud_request('https://elsewhere.example','secret')
    def test_sse_multiline_and_comments(self):
        events=list(run.sse(io.BytesIO(b':keepalive\n\ndata: {\ndata: "a":1}\n\ndata: [DONE]\n\n')))
        self.assertEqual(events,[None,'{\n"a":1}','[DONE]'])
    def fixture(self, done=True, reasoning=''):
        packets=[{'model':run.MODEL,'choices':[{'index':0,'delta':{'content':'[["a","b"]]','reasoning_content':reasoning},'finish_reason':None}]},
                 {'choices':[{'index':0,'delta':{},'finish_reason':'stop'}],'usage':{'completion_tokens':10,'prompt_tokens':20}}]
        text=''.join('data: '+json.dumps(p)+'\n\n' for p in packets)
        if done:text+='data: [DONE]\n\n'
        return io.BytesIO(text.encode())
    def test_cloud_D_is_array_protocol_and_usage_last_chunk(self):
        with patch.object(run.base.OPENER,'open',return_value=self.fixture()):
            row,packets,body=run.query_cloud({'id':'x','source':'a','translation':'b'},'D','synthetic','unit-test-secret')
        self.assertTrue(row['protocolSucceeded']);self.assertEqual(row['eval_count'],10)
        self.assertEqual(body['thinking'],{'type':'disabled'});self.assertNotIn('seed',body)
        self.assertNotIn('unit-test-secret',json.dumps([row,packets,body]))
    def test_missing_done_or_unexpected_thinking_cannot_succeed(self):
        for done,thinking in [(False,''),(True,'reasoning')]:
            with patch.object(run.base.OPENER,'open',return_value=self.fixture(done,thinking)):
                row,_,_=run.query_cloud({'id':'x','source':'a','translation':'b'},'C','synthetic','secret')
            self.assertFalse(row['protocolSucceeded'])
    def test_round_pairing_does_not_collapse_cloud_repetitions(self):
        rows=[]
        for rep in range(3):
            for arm in ['C','D']:
                rows.append({'caseID':'x','seed':None,'repetition':rep,'model':'deepseek','arm':arm,
                             'protocolSucceeded':True,'formatValid':True,'normalizedGroups':[{}],
                             'completionMs':100,'rawOutput':'[]'})
        result=review.performance(rows)
        self.assertEqual(result['pairedSuccessfulFixtures']['deepseek-C-to-D']['completionRatio']['n'],3)

if __name__=='__main__':unittest.main()

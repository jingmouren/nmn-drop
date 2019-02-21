from typing import Dict, Optional, List, Any

import torch
import torch.nn
from allennlp.common import Registrable
from allennlp.modules import Seq2SeqEncoder, SimilarityFunction, TextFieldEmbedder, TimeDistributed, FeedForward
from allennlp.modules.matrix_attention.legacy_matrix_attention import LegacyMatrixAttention
from allennlp.nn import InitializerApplicator, RegularizerApplicator
from allennlp.modules.matrix_attention.matrix_attention import MatrixAttention
from allennlp.nn.util import masked_softmax, weighted_sum, replace_masked_values
import utils.util as myutils

class DecompAtt(torch.nn.Module, Registrable):
    def __init__(self,
                 attend_feedforward: FeedForward,
                 similarity_function: SimilarityFunction,
                 compare_feedforward: FeedForward,
                 aggregate_feedforward: FeedForward,
                 initializer: InitializerApplicator = InitializerApplicator(),
                 regularizer: Optional[RegularizerApplicator] = None):
        super(DecompAtt, self).__init__()

        self._attend_feedforward = TimeDistributed(attend_feedforward)
        self._matrix_attention = LegacyMatrixAttention(similarity_function)
        self._compare_feedforward = TimeDistributed(compare_feedforward)
        self._aggregate_feedforward = aggregate_feedforward

        self._num_labels = 1

        # check_dimensions_match(text_field_embedder.get_output_dim(), attend_feedforward.get_input_dim(),
        #                        "text field embedding dim", "attend feedforward input dim")
        # check_dimensions_match(aggregate_feedforward.get_output_dim(), self._num_labels,
        #                        "final output dimension", "number of labels")


    def forward(self, embedded_premise, embedded_hypothesis, premise_mask, hypothesis_mask,
                debug=None, **kwargs):
        weighted_premise = False
        noprojection = True

        projected_premise = self._attend_feedforward(embedded_premise)
        projected_hypothesis = self._attend_feedforward(embedded_hypothesis)
        # Shape: (batch_size, premise_length, hypothesis_length)
        if noprojection:
            similarity_matrix = self._matrix_attention(embedded_premise, embedded_hypothesis)
        else:
            similarity_matrix = self._matrix_attention(projected_premise, projected_hypothesis)

        # Shape: (batch_size, premise_length) -- measures the importance of each premise token
        premise_importance_scores = (similarity_matrix*hypothesis_mask.unsqueeze(1)).sum(dim=2)
        premise_importance_distribution = masked_softmax(premise_importance_scores, mask=premise_mask)

        if debug:
            tokenized_contexts = kwargs['tokenized_contexts']
            tokenized_query = kwargs['tokenized_query']
            closest_context = myutils.tocpuNPList(kwargs['closest_context'])
            similarity_matrix_maked = replace_masked_values(similarity_matrix, premise_mask.unsqueeze(2), -1e7)
            similarity_matrix_list = myutils.round_all(myutils.tocpuNPList(similarity_matrix_maked), 3)
            # List of sum_qtoken_sim scores for (clostest) context tokens
            premise_impsc_masked = replace_masked_values(premise_importance_scores, premise_mask, -1e7)
            premise_impsc_list = myutils.round_all(myutils.tocpuNPList(premise_impsc_masked[closest_context]), 3)
            premise_impdt_list = myutils.round_all(myutils.tocpuNPList(
                    premise_importance_distribution[closest_context]), 3)

            print()
            print(' '.join(tokenized_query))
            c_idx, context_text = closest_context, tokenized_contexts[closest_context]
            print(' '.join(context_text))
            for q_idx, qt in enumerate(tokenized_query):
                print(f"Querytoken: {qt}")
                sim_mat = [c2qsim[q_idx] for c2qsim in similarity_matrix_list[c_idx]]  # [:][q_idx]
                topcidxs = myutils.topKindices(sim_mat, 10)
                print([(context_text[ctidx], sim_mat[ctidx]) for ctidx in topcidxs])
            print("Context importance:")
            topcidxs = myutils.topKindices(premise_impsc_list, 10)
            # print(topcidxs)
            # print(len(context_text))
            print([(context_text[ctidx], premise_impsc_list[ctidx], premise_impdt_list[ctidx]) for ctidx in topcidxs])

            # print()
            # print(premise_importance_distribution[0])
            # print()
            # print(premise_importance_distribution[1])

        # Shape: (batch_size, premise_length, hypothesis_length)
        p2h_attention = masked_softmax(similarity_matrix, hypothesis_mask)
        # Shape: (batch_size, premise_length, embedding_dim)
        attended_hypothesis = weighted_sum(embedded_hypothesis, p2h_attention)

        # Shape: (batch_size, hypothesis_length, premise_length)
        h2p_attention = masked_softmax(similarity_matrix.transpose(1, 2).contiguous(), premise_mask)
        # Shape: (batch_size, hypothesis_length, embedding_dim)
        attended_premise = weighted_sum(embedded_premise, h2p_attention)

        premise_compare_input = torch.cat([embedded_premise, attended_hypothesis], dim=-1)
        hypothesis_compare_input = torch.cat([embedded_hypothesis, attended_premise], dim=-1)

        # Shape: (batch_size, premise_length, embedding_dim)
        compared_premise = self._compare_feedforward(premise_compare_input)
        compared_premise = compared_premise * premise_mask.unsqueeze(-1)
        # Shape: (batch_size, compare_dim)
        if weighted_premise:
            compared_premise = (compared_premise*premise_importance_distribution.unsqueeze(2)).sum(dim=1)
        else:
            compared_premise = compared_premise.sum(dim=1)

        # Shape: (batch_size, hypothesis_length, embedding_dim)
        compared_hypothesis = self._compare_feedforward(hypothesis_compare_input)
        compared_hypothesis = compared_hypothesis * hypothesis_mask.unsqueeze(-1)
        # Shape: (batch_size, compare_dim)
        compared_hypothesis = compared_hypothesis.sum(dim=1)

        aggregate_input = torch.cat([compared_premise, compared_hypothesis], dim=-1)
        label_logits = self._aggregate_feedforward(aggregate_input)
        label_probs = torch.nn.functional.softmax(label_logits, dim=-1)

        if debug:
            print(f"AnsProb: {label_probs[kwargs['closest_context'], 0]}")
            print()

        output_dict = {"label_logits": label_logits,
                       "label_probs": label_probs,
                       "h2p_attention": h2p_attention,
                       "p2h_attention": p2h_attention}

        return output_dict

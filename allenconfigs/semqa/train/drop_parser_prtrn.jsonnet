local utils = import 'utils.libsonnet';

// This can be either 1) glove 2) bidaf 3) elmo
local tokenidx = std.extVar("TOKENIDX");


local token_embed_dim =
  if tokenidx == "glove" then 100
  else if tokenidx == "bidaf" then 200
  else if tokenidx == "elmo" then 1024
  else if tokenidx == "glovechar" then 200
  else if tokenidx == "elmoglove" then 1124;


local attendff_inputdim =
  if tokenidx == "glove" then 100
  else if tokenidx == "bidaf" then 200
  else if tokenidx == "elmo" then 1024
  else if tokenidx == "glovechar" then 200
  else if tokenidx == "elmoglove" then 1124;


local compareff_inputdim =
  if tokenidx == "glove" then 200
  else if tokenidx == "bidaf" then 400
  else if tokenidx == "elmo" then 2048
  else if tokenidx == "glovechar" then 400
  else if tokenidx == "elmoglove" then 2248;


{
    "dataset_reader": {
      "type": std.extVar("DATASET_READER"),
      "lazy": false,
      "skip_instances": true,
      "passage_length_limit": 400,
      "question_length_limit": 100,
      "token_indexers": {
          "tokens": {
              "type": "single_id",
              "lowercase_tokens": true
          },
          "token_characters": {
              "type": "characters",
              "min_padding_length": 5
          }
      },
    },

    "validation_dataset_reader": {
      "type": std.extVar("DATASET_READER"),
      "lazy": false,
      "skip_instances": false,
      "token_indexers": {
          "tokens": {
              "type": "single_id",
              "lowercase_tokens": true
          },
          "token_characters": {
              "type": "characters",
              "min_padding_length": 5
          }
      },
    },

    "vocabulary": {
        "min_count": {
            "token_characters": 200
        },
        "pretrained_files": {
            "tokens": std.extVar("WORDEMB_FILE"),
        },
        "only_include_pretrained_words": true,
        "directory_path": "./resources/semqa/naqanet/vocabulary",
        "extend": true
    },

    "train_data_path": std.extVar("TRAINING_DATA_FILE"),
    "validation_data_path": std.extVar("VAL_DATA_FILE"),
  //  "test_data_path": std.extVar("testfile"),


    "model": {
         "type": "drop_parser",

        "text_field_embedder": {
            "_pretrained": {
                "archive_file": "./resources/semqa/naqanet/naqanet-2019.03.01.tar.gz",
                "module_path": "_text_field_embedder", // path to reach transfer module from pretrained model
                "freeze": false
            }
        },

        "transitionfunc_attention": {
          "type": "dot_product",
          "normalize": true
        },
        "num_highway_layers": 2,

        "phrase_layer": {
            "type": "qanet_encoder",
            "input_dim": 128,
            "hidden_dim": 128,
            "attention_projection_dim": 128,
            "feedforward_hidden_dim": 128,
            "num_blocks": 1,
            "num_convs_per_block": 4,
            "conv_kernel_size": 7,
            "num_attention_heads": 8,
            "dropout_prob": 0.1,
            "layer_dropout_undecayed_prob": 0.1,
            "attention_dropout_prob": 0
        },

//        "phrase_layer": {
//            "type": "gru",
//            "input_size": 300,
//            "hidden_size": 64,
//            "num_layers": 2,
//            "dropout": 0.2,
//            "bidirectional": true
//        },

        "matrix_attention_layer": {
            "type": "linear",
            "tensor_1_dim": 128,
            "tensor_2_dim": 128,
            "combination": "x,y,x*y"
        },
        "modeling_layer": {
            "type": "qanet_encoder",
            "input_dim": 128,
            "hidden_dim": 128,
            "attention_projection_dim": 128,
            "feedforward_hidden_dim": 128,
            "num_blocks": 7,
            "num_convs_per_block": 2,
            "conv_kernel_size": 5,
            "num_attention_heads": 8,
            "dropout_prob": 0.1,
            "layer_dropout_undecayed_prob": 0.1,
            "attention_dropout_prob": 0
        },

    //    "passage_token_to_date": {
    //        "type": "stacked_self_attention",
    //        "input_dim": 128,
    //        "hidden_dim": 128,
    //        "projection_dim": 128,
    //        "feedforward_hidden_dim": 256,
    //        "num_layers": 3,
    //        "num_attention_heads": 4,
    //    },

        "passage_attention_to_span": {
            "type": "gru",
            "input_size": 4,
            "hidden_size": 20,
            "num_layers": 3,
            "bidirectional": true,
        },

        "question_attention_to_span": {
            "type": "gru",
            "input_size": 4,
            "hidden_size": 20,
            "num_layers": 3,
            "bidirectional": true,
        },

        "bidafutils":
            if tokenidx == "bidaf" then {
                "bidaf_model_path": std.extVar("BIDAF_MODEL_TAR"),
                "bidaf_wordemb_file": std.extVar("BIDAF_WORDEMB_FILE"),
            }
        ,
        "action_embedding_dim": 100,

        "beam_size": utils.parse_number(std.extVar("BEAMSIZE")),

//        "decoder_beam_search": {
//            "beam_size": utils.parse_number(std.extVar("BEAMSIZE")),
//        },

        "qp_sim_key": std.extVar("QP_SIM_KEY"),
        "sim_key": std.extVar("SIM_KEY"),

        "max_decoding_steps": utils.parse_number(std.extVar("MAX_DECODE_STEP")),
        "dropout": utils.parse_number(std.extVar("DROPOUT")),

        "regularizer": [
          [
              ".*",
              {
                  "type": "l2",
                  "alpha": 1e-7,
              }
          ]
        ],

        "initializers":
            [
                ["^_embedding_proj_layer|^_highway_layer|^_encoding_proj_layer|^_phrase_layer", //|^_matrix_attention",
                   {
                       "type": "pretrained",
                       "weights_file_path": "./resources/semqa/naqanet/weights.th"
                   },
                ],
                [".*_text_field_embedder.*", "prevent"]
            ],

        "goldactions": utils.boolparser(std.extVar("GOLDACTIONS")),
        "goldprogs": utils.boolparser(std.extVar("GOLDPROGS")),
        "denotationloss": utils.boolparser(std.extVar("DENLOSS")),
        "excloss": utils.boolparser(std.extVar("EXCLOSS")),
        "qattloss": utils.boolparser(std.extVar("QATTLOSS")),
        "mmlloss": utils.boolparser(std.extVar("MMLLOSS")),
        "debug": utils.boolparser(std.extVar("DEBUG"))
    },

    "iterator": {
        "type": "filter",
        "track_epoch": true,
        "batch_size": std.extVar("BS"),
//      "max_instances_in_memory":
        "filter_instances": utils.boolparser(std.extVar("SUPFIRST")),
        "filter_for_epochs": utils.parse_number(std.extVar("SUPEPOCHS")),
    },

    "validation_iterator": {
        "type": "basic",
        "track_epoch": true,
        "batch_size": std.extVar("BS")
    },


    "trainer": {
        "num_serialized_models_to_keep": 10,
        "grad_norm": 5,
        "patience": 20,
        "cuda_device": utils.parse_number(std.extVar("GPU")),
        "num_epochs": utils.parse_number(std.extVar("EPOCHS")),
        "shuffle": true,
        "optimizer": {
            "type": "adam",
            "lr": utils.parse_number(std.extVar("LR")),
            "betas": [
                0.8,
                0.999
            ],
            "eps": 1e-07
          },
        "moving_average": {
            "type": "exponential",
            "decay": 0.9999
        },
        "summary_interval": 100,
        "should_log_parameter_statistics": false,
        "validation_metric": "+f1"
    },

    "random_seed": utils.parse_number(std.extVar("SEED")),
    "numpy_seed": utils.parse_number(std.extVar("SEED")),
    "pytorch_seed": utils.parse_number(std.extVar("SEED"))

}
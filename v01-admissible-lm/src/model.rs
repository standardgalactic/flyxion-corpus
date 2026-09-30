use crate::mat::Mat;
use rand::{Rng, SeedableRng};

/// Character-level MLP language model (Bengio-2003 / makemore-MLP shape):
/// concatenated context embeddings -> tanh hidden layer -> softmax over
/// vocab. Forward and backward are both written out explicitly below --
/// no autodiff engine -- so every gradient in this file is checkable by
/// hand against the math in the comments, the same "one architecture,
/// fully inspectable" posture as Ullis.
#[derive(Clone)]
pub struct Model {
    pub vocab_size: usize,
    pub block_size: usize,
    pub emb_dim: usize,
    pub hidden_dim: usize,

    pub emb: Mat, // (vocab_size x emb_dim)
    pub w1: Mat,  // (block_size*emb_dim x hidden_dim)
    pub b1: Mat,  // (1 x hidden_dim)
    pub w2: Mat,  // (hidden_dim x vocab_size)
    pub b2: Mat,  // (1 x vocab_size)
}

#[derive(Clone)]
pub struct Grads {
    pub emb: Mat,
    pub w1: Mat,
    pub b1: Mat,
    pub w2: Mat,
    pub b2: Mat,
}

impl Grads {
    fn zeros_like(m: &Model) -> Self {
        Grads {
            emb: Mat::zeros(m.emb.rows, m.emb.cols),
            w1: Mat::zeros(m.w1.rows, m.w1.cols),
            b1: Mat::zeros(m.b1.rows, m.b1.cols),
            w2: Mat::zeros(m.w2.rows, m.w2.cols),
            b2: Mat::zeros(m.b2.rows, m.b2.cols),
        }
    }

    fn scale_in_place(&mut self, s: f32) {
        for v in self.emb.data.iter_mut() { *v *= s; }
        for v in self.w1.data.iter_mut() { *v *= s; }
        for v in self.b1.data.iter_mut() { *v *= s; }
        for v in self.w2.data.iter_mut() { *v *= s; }
        for v in self.b2.data.iter_mut() { *v *= s; }
    }

    /// Cosine similarity between two gradient sets, treating all five
    /// tensors together as one flattened vector (via running dot/norm
    /// accumulation -- never materializes a concatenated Vec).
    pub fn cosine_similarity(a: &Grads, b: &Grads) -> f32 {
        let mut dot = 0.0f64;
        let mut na = 0.0f64;
        let mut nb = 0.0f64;
        for (pa, pb) in [
            (&a.emb, &b.emb),
            (&a.w1, &b.w1),
            (&a.b1, &b.b1),
            (&a.w2, &b.w2),
            (&a.b2, &b.b2),
        ] {
            for (x, y) in pa.data.iter().zip(pb.data.iter()) {
                dot += (*x as f64) * (*y as f64);
                na += (*x as f64) * (*x as f64);
                nb += (*y as f64) * (*y as f64);
            }
        }
        if na == 0.0 || nb == 0.0 {
            return 0.0;
        }
        (dot / (na.sqrt() * nb.sqrt())) as f32
    }

    fn is_finite(&self) -> bool {
        [&self.emb, &self.w1, &self.b1, &self.w2, &self.b2]
            .iter()
            .all(|m| m.data.iter().all(|v| v.is_finite()))
    }
}

pub struct ForwardCache {
    pub ctx: Vec<usize>,
    pub x: Mat,      // (1 x D) concatenated embeddings
    pub h: Mat,      // (1 x H) post-tanh
    pub probs: Mat,  // (1 x V)
    pub target: usize,
    pub loss: f32,
}

impl Model {
    pub fn new(vocab_size: usize, block_size: usize, emb_dim: usize, hidden_dim: usize, seed: u64) -> Self {
        let mut rng = rand::rngs::StdRng::seed_from_u64(seed);
        let d = block_size * emb_dim;
        let scale_emb = 1.0 / (emb_dim as f32).sqrt();
        let scale_w1 = 1.0 / (d as f32).sqrt();
        let scale_w2 = 1.0 / (hidden_dim as f32).sqrt();

        let emb = Mat::from_fn(vocab_size, emb_dim, |_, _| rng.gen_range(-1.0..1.0) * scale_emb);
        let w1 = Mat::from_fn(d, hidden_dim, |_, _| rng.gen_range(-1.0..1.0) * scale_w1);
        let b1 = Mat::zeros(1, hidden_dim);
        let w2 = Mat::from_fn(hidden_dim, vocab_size, |_, _| rng.gen_range(-1.0..1.0) * scale_w2);
        let b2 = Mat::zeros(1, vocab_size);

        Model { vocab_size, block_size, emb_dim, hidden_dim, emb, w1, b1, w2, b2 }
    }

    fn embed_context(&self, ctx: &[usize]) -> Mat {
        let d = self.block_size * self.emb_dim;
        let mut x = Mat::zeros(1, d);
        for (pos, &tok) in ctx.iter().enumerate() {
            for j in 0..self.emb_dim {
                x.set(0, pos * self.emb_dim + j, self.emb.get(tok, j));
            }
        }
        x
    }

    pub fn forward(&self, ctx: &[usize], target: usize) -> ForwardCache {
        let x = self.embed_context(ctx);

        let h_pre = x.matmul(&self.w1).add_row_broadcast(&self.b1);
        let h = Mat::from_fn(h_pre.rows, h_pre.cols, |r, c| h_pre.get(r, c).tanh());

        let logits = h.matmul(&self.w2).add_row_broadcast(&self.b2);

        // softmax with max-subtraction for numerical stability
        let max_logit = logits.data.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
        let exps: Vec<f32> = logits.data.iter().map(|&v| (v - max_logit).exp()).collect();
        let sum: f32 = exps.iter().sum();
        let probs = Mat { rows: 1, cols: self.vocab_size, data: exps.iter().map(|&e| e / sum).collect() };

        let p_target = probs.get(0, target).max(1e-9);
        let loss = -p_target.ln();

        ForwardCache { ctx: ctx.to_vec(), x, h, probs, target, loss }
    }

    /// Backward pass for one cached forward call. Derivation:
    ///   dlogits = probs; dlogits[target] -= 1
    ///   dW2 = h^T @ dlogits;  db2 = dlogits
    ///   dh  = dlogits @ W2^T; dh_pre = dh * (1 - h^2)   [tanh']
    ///   dW1 = x^T @ dh_pre;   db1 = dh_pre
    ///   dx  = dh_pre @ W1^T  -> scattered back into embedding rows
    pub fn backward(&self, cache: &ForwardCache) -> Grads {
        let mut dlogits = cache.probs.clone();
        dlogits.add_at(0, cache.target, -1.0);

        let dw2 = cache.h.transpose().matmul(&dlogits);
        let db2 = dlogits.clone();

        let dh = dlogits.matmul(&self.w2.transpose());
        let dh_pre = Mat::from_fn(dh.rows, dh.cols, |r, c| {
            let hv = cache.h.get(r, c);
            dh.get(r, c) * (1.0 - hv * hv)
        });

        let dw1 = cache.x.transpose().matmul(&dh_pre);
        let db1 = dh_pre.clone();

        let dx = dh_pre.matmul(&self.w1.transpose());

        let mut demb = Mat::zeros(self.emb.rows, self.emb.cols);
        for (pos, &tok) in cache.ctx.iter().enumerate() {
            for j in 0..self.emb_dim {
                demb.add_at(tok, j, dx.get(0, pos * self.emb_dim + j));
            }
        }

        Grads { emb: demb, w1: dw1, b1: db1, w2: dw2, b2: db2 }
    }

    /// Average loss and gradient over a batch of (context, target) pairs.
    pub fn batch_grad(&self, batch: &[(Vec<usize>, usize)]) -> (f32, Grads) {
        let mut total = Grads::zeros_like(self);
        let mut total_loss = 0.0f32;
        for (ctx, target) in batch {
            let cache = self.forward(ctx, *target);
            total_loss += cache.loss;
            let g = self.backward(&cache);
            add_grads_in_place(&mut total, &g);
        }
        let n = batch.len().max(1) as f32;
        total.scale_in_place(1.0 / n);
        (total_loss / n, total)
    }

    /// Same math as forward(), minus the loss/target -- used for sampling.
    pub fn probs_for(&self, ctx: &[usize]) -> Mat {
        let x = self.embed_context(ctx);
        let h_pre = x.matmul(&self.w1).add_row_broadcast(&self.b1);
        let h = Mat::from_fn(h_pre.rows, h_pre.cols, |r, c| h_pre.get(r, c).tanh());
        let logits = h.matmul(&self.w2).add_row_broadcast(&self.b2);
        let max_logit = logits.data.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
        let exps: Vec<f32> = logits.data.iter().map(|&v| (v - max_logit).exp()).collect();
        let sum: f32 = exps.iter().sum();
        Mat { rows: 1, cols: self.vocab_size, data: exps.iter().map(|&e| e / sum).collect() }
    }

    pub fn apply_update(&mut self, grads: &Grads, lr: f32) {
        apply_in_place(&mut self.emb, &grads.emb, lr);
        apply_in_place(&mut self.w1, &grads.w1, lr);
        apply_in_place(&mut self.b1, &grads.b1, lr);
        apply_in_place(&mut self.w2, &grads.w2, lr);
        apply_in_place(&mut self.b2, &grads.b2, lr);
    }
}

pub fn grads_finite(g: &Grads) -> bool {
    g.is_finite()
}

fn add_grads_in_place(total: &mut Grads, g: &Grads) {
    for (t, s) in [
        (&mut total.emb, &g.emb),
        (&mut total.w1, &g.w1),
        (&mut total.b1, &g.b1),
        (&mut total.w2, &g.w2),
        (&mut total.b2, &g.b2),
    ] {
        for (a, b) in t.data.iter_mut().zip(s.data.iter()) {
            *a += *b;
        }
    }
}

fn apply_in_place(param: &mut Mat, grad: &Mat, lr: f32) {
    for (p, g) in param.data.iter_mut().zip(grad.data.iter()) {
        *p -= lr * g;
    }
}

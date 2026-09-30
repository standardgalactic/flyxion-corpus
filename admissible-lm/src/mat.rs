//! Minimal dense matrix type. No autodiff -- gradients for the model in
//! `model.rs` are derived by hand and computed explicitly in its
//! `backward()`. This keeps the whole numerical path inspectable, in the
//! same spirit as Ullis keeping ternary/RMSNorm kernels checked against a
//! CPU reference rather than trusting a framework's internals.

#[derive(Clone, Debug)]
pub struct Mat {
    pub rows: usize,
    pub cols: usize,
    pub data: Vec<f32>,
}

impl Mat {
    pub fn zeros(rows: usize, cols: usize) -> Self {
        Mat { rows, cols, data: vec![0.0; rows * cols] }
    }

    pub fn from_fn<F: FnMut(usize, usize) -> f32>(rows: usize, cols: usize, mut f: F) -> Self {
        let mut data = Vec::with_capacity(rows * cols);
        for r in 0..rows {
            for c in 0..cols {
                data.push(f(r, c));
            }
        }
        Mat { rows, cols, data }
    }

    #[inline]
    pub fn get(&self, r: usize, c: usize) -> f32 {
        self.data[r * self.cols + c]
    }

    #[inline]
    pub fn set(&mut self, r: usize, c: usize, v: f32) {
        self.data[r * self.cols + c] = v;
    }

    #[inline]
    pub fn add_at(&mut self, r: usize, c: usize, v: f32) {
        self.data[r * self.cols + c] += v;
    }

    /// self (rows x k) * other (k x cols) -> (rows x cols)
    pub fn matmul(&self, other: &Mat) -> Mat {
        assert_eq!(self.cols, other.rows, "matmul shape mismatch");
        let mut out = Mat::zeros(self.rows, other.cols);
        for r in 0..self.rows {
            for k in 0..self.cols {
                let a = self.get(r, k);
                if a == 0.0 {
                    continue;
                }
                for c in 0..other.cols {
                    out.add_at(r, c, a * other.get(k, c));
                }
            }
        }
        out
    }

    pub fn transpose(&self) -> Mat {
        Mat::from_fn(self.cols, self.rows, |r, c| self.get(c, r))
    }

    pub fn add(&self, other: &Mat) -> Mat {
        assert_eq!((self.rows, self.cols), (other.rows, other.cols));
        Mat::from_fn(self.rows, self.cols, |r, c| self.get(r, c) + other.get(r, c))
    }

    pub fn scale(&self, s: f32) -> Mat {
        Mat::from_fn(self.rows, self.cols, |r, c| self.get(r, c) * s)
    }

    pub fn add_row_broadcast(&self, bias: &Mat) -> Mat {
        // bias: (1 x cols)
        assert_eq!(bias.rows, 1);
        assert_eq!(self.cols, bias.cols);
        Mat::from_fn(self.rows, self.cols, |r, c| self.get(r, c) + bias.get(0, c))
    }
}
